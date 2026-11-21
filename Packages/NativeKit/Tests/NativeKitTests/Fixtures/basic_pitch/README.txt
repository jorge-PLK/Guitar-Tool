Basic Pitch (Spotify), nmp.onnx del paquete pip basic-pitch 0.4.0, Apache-2.0 (LICENSE y NOTICE en esta carpeta).
SHA-256 de model.onnx: 2c3c1d144bfa61ad236e92e169c13535c880469a12a047d4e73451f2c059a0ec (230444 bytes).
Entrada y referencias float32 crudas de Probes/P8-windows/ort-models/out/basic_pitch (parte 7.3):
  in_serving_default_input_2_0.bin  serving_default_input_2:0 (1,43844,1)
  ref_StatefulPartitionedCall_<k>.bin  ORT CPU en el Mac (:0 contorno (1,172,264), :1 nota y :2 onset (1,172,88))
  coreml_StatefulPartitionedCall_<k>.bin  Core ML de la app (umbrales 0,3 nota y 0,5 onset)
