# Paso de prueba de pc.sh: sale con el codigo pedido (comprueba que el codigo de salida llega al Mac).
param([int]$Code = 1)
Write-Output "TF:selftest sale con $Code"
exit $Code
