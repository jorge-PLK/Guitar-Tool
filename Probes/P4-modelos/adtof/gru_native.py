"""Traducción de nn.GRU (bidireccional, batch_first, 1 capa) a la operación nativa `gru` de MIL iOS18
(reset_after=True, semántica PyTorch/Keras) en lugar del while_loop por paso que genera coremltools 9.0
(52 s de modelo en T1 frente a 1,3 s en PyTorch).

Importar este módulo registra la traducción (override). Ejecutado como script, prueba una GRU pequeña contra
PyTorch con las dos asignaciones posibles de sesgos (bias / input_bias, no documentadas) y dice cuál coincide.
"""
import numpy as np
from coremltools.converters.mil import Builder as mb
from coremltools.converters.mil.frontend.torch.ops import _get_inputs
from coremltools.converters.mil.frontend.torch.torch_op_registry import register_torch_op

BIAS_SWAP = False   # False: bias = sesgo oculto (b_h*), input_bias = sesgo de entrada (b_i*)
ORDER = "rnz"       # orden de puertas que espera Core ML, en letras de PyTorch (n = o de Core ML)
REVERSE_OUT = True  # invertir en el tiempo la salida de la dirección "reverse"


def _reorder(w):
    """PyTorch [r | z | n] → orden ORDER de Core ML."""
    g = dict(zip("rzn", np.split(np.asarray(w, dtype=np.float32), 3)))
    return np.concatenate([g[c] for c in ORDER])


@register_torch_op(override=True)
def gru(context, node):
    inputs = _get_inputs(context, node, expected=9)
    x, wl = inputs[0], inputs[2]
    has_bias, num_layers = inputs[3].val, inputs[4].val
    bidirectional, batch_first = inputs[7].val, inputs[8].val
    assert has_bias and num_layers == 1 and bidirectional and batch_first, "solo el caso de ADTOF"
    xs = mb.transpose(x=x, perm=[1, 0, 2])                         # (s, b, I)
    outs, hs = [], []
    for d, direction in enumerate(("forward", "reverse")):
        wi, wh, bi, bh = (w.val for w in wl[4 * d: 4 * d + 4])
        H = wh.shape[1]
        b_hid, b_in = (_reorder(bi), _reorder(bh)) if BIAS_SWAP else (_reorder(bh), _reorder(bi))
        y, h = mb.gru(x=xs, initial_h=np.zeros((1, H), np.float32), weight_ih=_reorder(wi),
                      weight_hh=_reorder(wh), bias=b_hid, input_bias=b_in, direction=direction,
                      output_sequence=True, reset_after=True, name=f"{node.name}_{direction}")
        if direction == "reverse" and REVERSE_OUT:
            y = mb.reverse(x=y, axes=[0])        # Core ML da la salida inversa en orden de proceso
        outs.append(y)
        hs.append(mb.expand_dims(x=h, axes=[0]))
    y = mb.transpose(x=mb.concat(values=outs, axis=2), perm=[1, 0, 2])   # (b, s, 2H)
    context.add(y, node.outputs[0])
    context.add(mb.concat(values=hs, axis=0), node.outputs[1])


if __name__ == "__main__":
    import coremltools as ct
    import torch

    torch.manual_seed(0)
    g = torch.nn.GRU(16, 8, batch_first=True, bidirectional=True).eval()

    class W(torch.nn.Module):
        def __init__(self):
            super().__init__()
            self.g = g

        def forward(self, x):
            return self.g(x)[0]

    x = torch.randn(1, 50, 16)
    ref = W()(x).detach().numpy()
    import itertools
    for rev in (False, True):
        REVERSE_OUT = rev
        ml = ct.convert(torch.jit.trace(W(), x), inputs=[ct.TensorType(name="x", shape=(1, 50, 16))],
                        convert_to="mlprogram", compute_precision=ct.precision.FLOAT32,
                        minimum_deployment_target=ct.target.macOS15, compute_units=ct.ComputeUnit.CPU_ONLY)
        y = list(ml.predict({"x": x.numpy()}).values())[0]
        d = np.abs(y - ref)
        print(f"ORDER={ORDER} BIAS_SWAP={BIAS_SWAP} REVERSE_OUT={rev}: max diff fw {d[..., :8].max():.2e} bw {d[..., 8:].max():.2e}")
