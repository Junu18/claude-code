#!/bin/bash

# Full System Simulation Script (Master + Slave)
# Usage: ./run_full_sim.sh

echo "=========================================="
echo "  Full System Simulation"
echo "  Master + Slave SPI System"
echo "=========================================="

echo ""
echo "Compiling modules..."

# Compile all modules
iverilog -g2012 \
    -o sim_full_system.vvp \
    tick_gen.sv \
    spi_master.sv \
    spi_upcounter_cu.sv \
    spi_upcounter_dp.sv \
    master_top_fast.sv \
    spi_slave.sv \
    slave_controller.sv \
    fnd_controller.sv \
    slave_top.sv \
    tb_full_system.sv

if [ $? -ne 0 ]; then
    echo "Compilation failed!"
    exit 1
fi

# Run simulation
echo ""
echo "Running full system simulation..."
vvp sim_full_system.vvp

echo ""
echo "=========================================="
echo "  Simulation Complete!"
echo "  VCD file: full_system.vcd"
echo "=========================================="
echo ""
echo "To view waveforms:"
echo "  gtkwave full_system.vcd"
echo ""
