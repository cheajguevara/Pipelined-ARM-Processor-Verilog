param(
    [string]$VivadoBin = 'C:\Xilinx\2025.1\Vivado\bin',
    [string]$ArmBin = 'C:\Keil_v5\ARM\ARMCC\bin'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$synthDir = Join-Path $PSScriptRoot 'build\synth'
$simDir = Join-Path $PSScriptRoot 'build\post_synth'
New-Item -ItemType Directory -Force $synthDir, $simDir | Out-Null

function Invoke-Checked {
    param([string]$Executable, [string[]]$Arguments)
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Executable failed with exit code $LASTEXITCODE"
    }
}

Push-Location $synthDir
try {
    Invoke-Checked (Join-Path $VivadoBin 'vivado.bat') @(
        '-mode', 'batch', '-notrace', '-source', (Join-Path $PSScriptRoot 'run_synth.tcl'),
        '-log', 'vivado.log', '-journal', 'vivado.jou'
    )
    Invoke-Checked (Join-Path $VivadoBin 'vivado.bat') @(
        '-mode', 'batch', '-notrace', '-source', (Join-Path $PSScriptRoot 'write_post_synth.tcl'),
        '-log', 'netlist_export.log', '-journal', 'netlist_export.jou'
    )
} finally {
    Pop-Location
}

Invoke-Checked 'python' @(
    (Join-Path $PSScriptRoot 'run_uart.py'), '--simulator', 'questa', '--arm-bin', $ArmBin
)
Copy-Item (Join-Path $PSScriptRoot 'build\uart\uart_program.hex') (Join-Path $simDir 'uart_program.hex') -Force

Push-Location $simDir
try {
    Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') @(
        '-d', 'POST_SYNTH',
        (Join-Path $synthDir 'arm_core_funcsim.v'),
        (Join-Path $root 'rtl\sram_model.v'),
        (Join-Path $root 'rtl\uart_mmio.v'),
        (Join-Path $root 'rtl\irq_controller.v'),
        (Join-Path $root 'tb\instruction_memory.v'),
        (Join-Path $root 'tb\tb_uart_c.v'),
        (Join-Path $root 'tb\tb_irq_post_synth.v')
    )
    $tests = @(
        @{ Top = 'tb_uart_c'; Snapshot = 'uart_post'; Pass = 'PASS: ARM C firmware transmitted' },
        @{ Top = 'tb_irq_post_synth_forwarding'; Snapshot = 'irq_forwarding'; Pass = 'PASS: post-synthesis IRQ' },
        @{ Top = 'tb_irq_post_synth_no_forwarding'; Snapshot = 'irq_no_forwarding'; Pass = 'PASS: post-synthesis IRQ' }
    )
    foreach ($test in $tests) {
        $log = $test.Snapshot + '.log'
        if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log }
        Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @(
            ('work.' + $test.Top), 'work.glbl', '-L', 'unisims_ver', '-s', $test.Snapshot
        )
        Invoke-Checked (Join-Path $VivadoBin 'xsim.bat') @(
            $test.Snapshot, '-runall', '-log', $log
        )
        if (!(Select-String -LiteralPath $log -SimpleMatch -Pattern $test.Pass -Quiet) -or
            (Select-String -LiteralPath $log -Pattern '^\s*(Fatal|Error):' -Quiet)) {
            throw "$($test.Top) did not pass; see $log"
        }
    }
} finally {
    Pop-Location
}

Write-Host "Post-synthesis UART and IRQ tests passed. Logs: $simDir"
