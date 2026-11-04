$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\sim')
$vivadoBin = 'D:\AMDDesignTools\2025.2\Vivado\bin'
python ..\scripts\generate_test_vectors.py
python ..\scripts\generate_control_vectors.py
& "$vivadoBin\xvlog.bat" --sv ../rtl/dsp.v ../rtl/acquisition.v ../rtl/control_link.v ../rtl/remote_control.v fft_tb.v features_tb.v i2c_tb.v encoder_tb.v remote_tb.v link_control_tb.v
if ($LASTEXITCODE -ne 0) { throw 'Verilog compilation failed' }
foreach ($test in @('fft','features','i2c','encoder','remote','link_control')) {
    & "$vivadoBin\xelab.bat" "${test}_tb" -s "${test}_test"
    if ($LASTEXITCODE -ne 0) { throw "Elaboration failed: $test" }
    & "$vivadoBin\xsim.bat" "${test}_test" -runall -log "${test}_result.log"
    if ($LASTEXITCODE -ne 0 -or !(Select-String -Path "${test}_result.log" -Pattern 'RTL_PASS' -Quiet)) { throw "Simulation failed: $test" }
}
python ..\scripts\test_numeric.py
if ($LASTEXITCODE -ne 0) { throw 'Numeric / protocol tests failed' }
