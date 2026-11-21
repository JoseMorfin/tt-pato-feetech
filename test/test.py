import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

DIV = 4  # ciclos por bit = DIV + 1


async def pulso(dut, bit):
    dut.uio_in.value = int(dut.uio_in.value) | (1 << bit)
    await ClockCycles(dut.clk, 4)
    dut.uio_in.value = int(dut.uio_in.value) & ~(1 << bit)
    await ClockCycles(dut.clk, 4)


async def escribir(dut, b):
    dut.ui_in.value = b
    await pulso(dut, 0)


async def recibir_uart(dut, nbytes, cpb):
    """Decodifica TX (uo_out[0]) muestreando a mitad de bit."""
    out = []
    for _ in range(nbytes):
        while int(dut.uo_out.value) & 1:
            await RisingEdge(dut.clk)
        await ClockCycles(dut.clk, cpb // 2)
        assert (int(dut.uo_out.value) & 1) == 0, "start bit"
        v = 0
        for i in range(8):
            await ClockCycles(dut.clk, cpb)
            v |= (int(dut.uo_out.value) & 1) << i
        await ClockCycles(dut.clk, cpb)
        assert int(dut.uo_out.value) & 1, "stop bit"
        out.append(v)
    return out


async def iniciar(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    dut.ena.value = 1; dut.ui_in.value = 0; dut.uio_in.value = 0; dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10); dut.rst_n.value = 1; await ClockCycles(dut.clk, 5)
    dut.ui_in.value = DIV
    await pulso(dut, 2)


async def mandar(dut, cuerpo):
    for b in cuerpo:
        await escribir(dut, b)
    assert (int(dut.uo_out.value) >> 4) == (15 if len(cuerpo) >= 16 else len(cuerpo))
    rx = cocotb.start_soon(recibir_uart(dut, len(cuerpo) + 3, DIV + 1))
    await pulso(dut, 1)
    return await rx


@cocotb.test()
async def paquete_posicion(dut):
    """WRITE de posicion al servo 1 (dir 0x2A, 2048): FF FF 01 05 03 2A 00 08 chk."""
    await iniciar(dut)
    cuerpo = [0x01, 0x05, 0x03, 0x2A, 0x00, 0x08]
    got = await mandar(dut, cuerpo)
    chk = (~sum(cuerpo)) & 0xFF
    assert got == [0xFF, 0xFF] + cuerpo + [chk], [hex(x) for x in got]
    await ClockCycles(dut.clk, 20)
    assert (int(dut.uo_out.value) >> 1) & 1 == 0, "BUSY debe bajar"
    assert (int(dut.uio_out.value) >> 4) == (chk & 0xF)


@cocotb.test()
async def paquetes_aleatorios(dut):
    """20 paquetes aleatorios de 1 a 16 bytes."""
    await iniciar(dut)
    for _ in range(20):
        cuerpo = [random.randrange(256) for _ in range(random.randint(1, 16))]
        got = await mandar(dut, cuerpo)
        assert got == [0xFF, 0xFF] + cuerpo + [(~sum(cuerpo)) & 0xFF]
        await ClockCycles(dut.clk, 30)
