"""GLU por cortes para exportar a ONNX: x[..., :h] * sigmoid(x[..., h:]) en lugar de nn.GLU.

nn.GLU (y chunk/split) se exporta como Split(2) -> Sigmoid -> Mul. ONNX Runtime con DirectML, con la fusión de
grafo activa y los metacomandos de NVIDIA, calcula mal ese patrón tras un MatMul+Add (SNR ~0 dB en los mask
estimators de BS-RoFormer y del Mel-Band RoFormer lead/rhythm; RTX 3060, DirectML 1.15.4, 22/11/2026). Con dos
Slice el resultado es exacto y igual de rápido. Solo para los export a ONNX: la conversión a Core ML no lo usa.

El post-proceso equivalente sobre un ONNX ya exportado es Probes/P8-windows/ort-models/glu_slice.py."""


def use_slice_glu(model) -> int:
    """Cambia en su sitio cada nn.GLU de `model` por un GLU con dos cortes. Devuelve cuántos ha cambiado.

    Si el GLU va dentro de un nn.Sequential tras un nn.Linear, la mitad se fija con out_features // 2 (cortes
    con límites constantes en el ONNX); si no, se toma de la forma en tiempo de ejecución."""
    import torch
    from torch import nn

    class SliceGLU(nn.Module):
        def __init__(self, dim: int, half: int | None):
            super().__init__()
            self.dim, self.half = dim, half

        def forward(self, x):
            h = self.half if self.half is not None else x.shape[self.dim] // 2
            return x.narrow(self.dim, 0, h) * torch.sigmoid(x.narrow(self.dim, h, h))

    count = 0
    for parent in list(model.modules()):
        last_out = None
        for name, child in list(parent.named_children()):
            if isinstance(child, nn.GLU):
                half = last_out // 2 if isinstance(parent, nn.Sequential) and last_out else None
                setattr(parent, name, SliceGLU(child.dim, half))
                count += 1
            lins = [m for m in child.modules() if isinstance(m, nn.Linear)]
            last_out = lins[-1].out_features if lins else last_out
    return count
