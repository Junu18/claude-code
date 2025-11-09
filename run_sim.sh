#!/bin/bash

# SPI Master Simulation Script
# Usage: ./run_sim.sh [fast|normal]

MODE=${1:-fast}

echo "=========================================="
echo "  SPI Master Top Simulation"
echo "=========================================="

if [ "$MODE" == "fast" ]; then
    echo "Mode: FAST (1ms tick period)"
    TB_MODULE="tb_master_fast"
    VCD_FILE="master_top_fast.vcd"

    # Compile
    echo ""
    echo "Compiling modules..."
    iverilog -g2012 \
        -o sim_master_fast.vvp \
        tick_gen.sv \
        spi_master.sv \
        spi_upcounter_cu.sv \
        spi_upcounter_dp.sv \
        master_top_fast.sv \
        tb_master_fast.sv

    if [ $? -ne 0 ]; then
        echo "Compilation failed!"
        exit 1
    fi

    # Run simulation
    echo ""
    echo "Running simulation..."
    vvp sim_master_fast.vvp

else
    echo "Mode: NORMAL (100ms tick period)"
    TB_MODULE="tb_master_top"
    VCD_FILE="master_top.vcd"

    # Compile
    echo ""
    echo "Compiling modules..."
    iverilog -g2012 \
        -o sim_master.vvp \
        tick_gen.sv \
        spi_master.sv \
        spi_upcounter_cu.sv \
        spi_upcounter_dp.sv \
        master_top.sv \
        tb_master_top.sv

    if [ $? -ne 0 ]; then
        echo "Compilation failed!"
        exit 1
    fi

    # Run simulation
    echo ""
    echo "Running simulation..."
    vvp sim_master.vvp
fi

echo ""
echo "=========================================="
echo "  Simulation Complete!"
echo "  VCD file: $VCD_FILE"
echo "=========================================="
echo ""
echo "To view waveforms:"
echo "  gtkwave $VCD_FILE"
echo ""
