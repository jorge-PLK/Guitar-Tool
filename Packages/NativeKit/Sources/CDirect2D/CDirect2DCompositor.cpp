// Compositor del montaje con Direct2D + DirectWrite (plan, «Fase 7c», paso 7, parte 7.9). Ver CDirect2D.h.
#include "CDirect2D.h"

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <d2d1_1.h>
#include <d2d1_1helper.h>
#include <d2d1effects.h>
#include <dwrite.h>
#include <wrl/client.h>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <map>
#include <string>

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "dxguid.lib")
#pragma comment(lib, "d2d1.lib")
#pragma comment(lib, "dwrite.lib")

using Microsoft::WRL::ComPtr;

namespace {

struct Context {
    UINT32 width = 0, height = 0;
    ComPtr<ID3D11Device> d3d;
    ComPtr<ID2D1Factory1> factory;
    ComPtr<ID2D1Device> device;
    ComPtr<ID2D1DeviceContext> dc;
    ComPtr<ID2D1Bitmap1> target, readback;
    ComPtr<ID2D1SolidColorBrush> black, white;
    ComPtr<IDWriteFactory> dwrite;
    std::wstring family = L"Segoe UI";
    std::map<int32_t, ComPtr<ID2D1Bitmap1>> sources;
    std::map<int32_t, ComPtr<ID2D1Bitmap1>> plates;
    bool drawing = false;
};

#define TRY(x) do { HRESULT hr_ = (x); if (FAILED(hr_)) return hr_; } while (0)

D2D1_BITMAP_PROPERTIES1 props(D2D1_BITMAP_OPTIONS options, D2D1_ALPHA_MODE alpha = D2D1_ALPHA_MODE_PREMULTIPLIED) {
    return D2D1::BitmapProperties1(options, D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, alpha), 96, 96);
}

HRESULT makeDevice(Context *c, bool allowHardware, TFD2DInfo *info) {
    const D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1,
                                        D3D_FEATURE_LEVEL_10_0, D3D_FEATURE_LEVEL_9_3};
    const UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
    HRESULT hr = E_FAIL;
    bool hardware = false;
    if (allowHardware) {
        hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags, levels, ARRAYSIZE(levels), D3D11_SDK_VERSION,
                               &c->d3d, nullptr, nullptr);
        hardware = SUCCEEDED(hr);
    }
    if (FAILED(hr)) {
        hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr, flags, levels, ARRAYSIZE(levels), D3D11_SDK_VERSION,
                               &c->d3d, nullptr, nullptr);
    }
    TRY(hr);
    ComPtr<IDXGIDevice> dxgi;
    TRY(c->d3d.As(&dxgi));
    ComPtr<IDXGIAdapter> adapter;
    if (info) {
        std::memset(info, 0, sizeof(*info));
        if (SUCCEEDED(dxgi->GetAdapter(&adapter))) {
            DXGI_ADAPTER_DESC desc = {};
            if (SUCCEEDED(adapter->GetDesc(&desc))) {
                for (int i = 0; i < 127 && desc.Description[i]; i++) info->adapter[i] = (uint16_t)desc.Description[i];
                // «Microsoft Basic Render Driver» (0x1414:0x8C) es WARP aunque se haya pedido hardware.
                if (desc.VendorId == 0x1414 && desc.DeviceId == 0x8C) hardware = false;
            }
        }
        info->hardware = hardware ? 1 : 0;
    }
    D2D1_FACTORY_OPTIONS fo = {};
    TRY(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, __uuidof(ID2D1Factory1), &fo,
                          reinterpret_cast<void **>(c->factory.GetAddressOf())));
    TRY(c->factory->CreateDevice(dxgi.Get(), &c->device));
    TRY(c->device->CreateDeviceContext(D2D1_DEVICE_CONTEXT_OPTIONS_NONE, &c->dc));
    c->dc->SetUnitMode(D2D1_UNIT_MODE_PIXELS);
    c->dc->SetDpi(96, 96);
    c->dc->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
    const D2D1_SIZE_U size = D2D1::SizeU(c->width, c->height);
    TRY(c->dc->CreateBitmap(size, nullptr, 0, props(D2D1_BITMAP_OPTIONS_TARGET), &c->target));
    TRY(c->dc->CreateBitmap(size, nullptr, 0, props(D2D1_BITMAP_OPTIONS_CPU_READ | D2D1_BITMAP_OPTIONS_CANNOT_DRAW), &c->readback));
    TRY(c->dc->CreateSolidColorBrush(D2D1::ColorF(0, 0, 0, 1), &c->black));
    TRY(c->dc->CreateSolidColorBrush(D2D1::ColorF(1, 1, 1, 1), &c->white));
    TRY(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory), reinterpret_cast<IUnknown **>(c->dwrite.GetAddressOf())));
    return S_OK;
}

/// Una línea de texto medida como la imagen de Core Text del Mac.
struct Line {
    ComPtr<IDWriteTextLayout> layout;
    float boxWidth = 0, boxHeight = 0, descent = 0, layoutBaseline = 0;
};

HRESULT measure(Context *c, const uint16_t *text, float size, bool bold, Line &out) {
    const wchar_t *w = reinterpret_cast<const wchar_t *>(text);
    const UINT32 n = (UINT32)wcslen(w);
    const DWRITE_FONT_WEIGHT weight = bold ? DWRITE_FONT_WEIGHT_BOLD : DWRITE_FONT_WEIGHT_REGULAR;
    ComPtr<IDWriteTextFormat> format;
    TRY(c->dwrite->CreateTextFormat(c->family.c_str(), nullptr, weight, DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL, size,
                                    L"", &format));
    TRY(format->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP));
    TRY(c->dwrite->CreateTextLayout(w, n, format.Get(), 100000.0f, 100000.0f, &out.layout));
    DWRITE_TEXT_METRICS tm = {};
    TRY(out.layout->GetMetrics(&tm));
    DWRITE_LINE_METRICS lm = {};
    UINT32 lines = 0;
    TRY(out.layout->GetLineMetrics(&lm, 1, &lines));
    // Ascendente y descendente de la fuente (los de `CTLineGetTypographicBounds`).
    ComPtr<IDWriteFontCollection> fonts;
    TRY(c->dwrite->GetSystemFontCollection(&fonts));
    UINT32 index = 0;
    BOOL exists = FALSE;
    TRY(fonts->FindFamilyName(c->family.c_str(), &index, &exists));
    if (!exists) return HRESULT_FROM_WIN32(ERROR_NOT_FOUND);
    ComPtr<IDWriteFontFamily> fam;
    TRY(fonts->GetFontFamily(index, &fam));
    ComPtr<IDWriteFont> font;
    TRY(fam->GetFirstMatchingFont(weight, DWRITE_FONT_STRETCH_NORMAL, DWRITE_FONT_STYLE_NORMAL, &font));
    DWRITE_FONT_METRICS fm = {};
    font->GetMetrics(&fm);
    const float ascent = fm.ascent * size / fm.designUnitsPerEm, descent = fm.descent * size / fm.designUnitsPerEm;
    out.boxWidth = std::ceil(tm.widthIncludingTrailingWhitespace);
    out.boxHeight = std::ceil(ascent + descent);
    out.descent = descent;
    out.layoutBaseline = lm.baseline;
    return S_OK;
}

HRESULT effect(Context *c, REFCLSID id, ComPtr<ID2D1Effect> &out) { return c->dc->CreateEffect(id, &out); }

/// Desenfoque gaussiano de `input` (calidad máxima; `hard`: sin desvanecer en el borde de la entrada).
HRESULT blur(Context *c, ID2D1Effect *inputEffect, ID2D1Image *input, float sigma, bool hard, ComPtr<ID2D1Effect> &out) {
    TRY(effect(c, CLSID_D2D1GaussianBlur, out));
    if (inputEffect) out->SetInputEffect(0, inputEffect); else out->SetInput(0, input);
    TRY(out->SetValue(D2D1_GAUSSIANBLUR_PROP_STANDARD_DEVIATION, sigma));
    TRY(out->SetValue(D2D1_GAUSSIANBLUR_PROP_OPTIMIZATION, D2D1_GAUSSIANBLUR_OPTIMIZATION_QUALITY));
    TRY(out->SetValue(D2D1_GAUSSIANBLUR_PROP_BORDER_MODE, hard ? D2D1_BORDER_MODE_HARD : D2D1_BORDER_MODE_SOFT));
    return S_OK;
}

/// Recorte a `r` y bordes extendidos (`clampedToExtent` de Core Image).
HRESULT cropClamp(Context *c, ID2D1Effect *inputEffect, ID2D1Image *input, D2D1_RECT_F r, ComPtr<ID2D1Effect> &out) {
    ComPtr<ID2D1Effect> crop;
    TRY(effect(c, CLSID_D2D1Crop, crop));
    if (inputEffect) crop->SetInputEffect(0, inputEffect); else crop->SetInput(0, input);
    TRY(crop->SetValue(D2D1_CROP_PROP_RECT, D2D1::Vector4F(r.left, r.top, r.right, r.bottom)));
    TRY(crop->SetValue(D2D1_CROP_PROP_BORDER_MODE, D2D1_BORDER_MODE_HARD));
    TRY(effect(c, CLSID_D2D1Border, out));
    out->SetInputEffect(0, crop.Get());
    TRY(out->SetValue(D2D1_BORDER_PROP_EDGE_MODE_X, D2D1_BORDER_EDGE_MODE_CLAMP));
    TRY(out->SetValue(D2D1_BORDER_PROP_EDGE_MODE_Y, D2D1_BORDER_EDGE_MODE_CLAMP));
    return S_OK;
}

void fillBlack(Context *c, D2D1_RECT_F r, float alpha) {
    if (alpha <= 0) return;
    c->black->SetOpacity(std::min(1.0f, alpha));
    c->dc->FillRectangle(r, c->black.Get());
    c->black->SetOpacity(1);
}

/// Contenido del recuadro en el destino actual: fuente recortada y escalada a `d`, o ajustada sobre su relleno.
HRESULT drawContent(Context *c, const TFD2DBox *b, D2D1_RECT_F d) {
    auto it = c->sources.find(b->slot);
    if (b->slot < 0 || it == c->sources.end() || !it->second) {
        fillBlack(c, d, 1);
        return S_OK;
    }
    ID2D1Bitmap1 *src = it->second.Get();
    const D2D1_SIZE_U ps = src->GetPixelSize();
    const float sw = (float)ps.width, sh = (float)ps.height;
    if (!b->fit) {
        const D2D1_RECT_F s = D2D1::RectF(b->cropX * sw, b->cropY * sh, (b->cropX + b->cropW) * sw, (b->cropY + b->cropH) * sh);
        c->dc->DrawBitmap(src, &d, 1.0f, D2D1_INTERPOLATION_MODE_LINEAR, &s, nullptr);
        return S_OK;
    }
    // «Mantener aspect ratio»: relleno = la toma ampliada hasta cubrir `d`, a escala q, extendida, desenfocada y
    // oscurecida; encima, la toma entera ajustada y centrada (`MontageRenderer.fitted` del Mac).
    const float w = d.right - d.left, h = d.bottom - d.top, cx = (d.left + d.right) / 2, cy = (d.top + d.bottom) / 2;
    const float fit = std::min(w / sw, h / sh), cover = std::max(w / sw, h / sh), q = b->fillScale > 0 ? b->fillScale : 1;
    ComPtr<ID2D1Effect> xf, clamp, soft;
    TRY(effect(c, CLSID_D2D12DAffineTransform, xf));
    xf->SetInput(0, src);
    const D2D1_MATRIX_3X2_F m = D2D1::Matrix3x2F::Translation(-sw / 2, -sh / 2) * D2D1::Matrix3x2F::Scale(cover * q, cover * q) *
                                D2D1::Matrix3x2F::Translation(cx * q, cy * q);
    TRY(xf->SetValue(D2D1_2DAFFINETRANSFORM_PROP_TRANSFORM_MATRIX, m));
    TRY(xf->SetValue(D2D1_2DAFFINETRANSFORM_PROP_INTERPOLATION_MODE, D2D1_2DAFFINETRANSFORM_INTERPOLATION_MODE_LINEAR));
    TRY(cropClamp(c, xf.Get(), nullptr, D2D1::RectF(d.left * q, d.top * q, d.right * q, d.bottom * q), clamp));
    TRY(blur(c, clamp.Get(), nullptr, b->fillBlur * q, true, soft));
    ComPtr<ID2D1Image> fill;
    soft->GetOutput(&fill);
    c->dc->PushAxisAlignedClip(d, D2D1_ANTIALIAS_MODE_ALIASED);
    D2D1_MATRIX_3X2_F old;
    c->dc->GetTransform(&old);
    c->dc->SetTransform(D2D1::Matrix3x2F::Scale(1 / q, 1 / q) * old);
    c->dc->DrawImage(fill.Get(), nullptr, nullptr, D2D1_INTERPOLATION_MODE_LINEAR, D2D1_COMPOSITE_MODE_SOURCE_OVER);
    c->dc->SetTransform(old);
    fillBlack(c, d, 1 - b->fillDim);
    const D2D1_RECT_F f = D2D1::RectF(cx - sw * fit / 2, cy - sh * fit / 2, cx + sw * fit / 2, cy + sh * fit / 2);
    c->dc->DrawBitmap(src, &f, 1.0f, D2D1_INTERPOLATION_MODE_LINEAR, nullptr, nullptr);
    c->dc->PopAxisAlignedClip();
    return S_OK;
}

} // namespace

extern "C" {

int32_t tfd2d_create(int32_t width, int32_t height, int32_t allowHardware, void **context, TFD2DInfo *info) {
    if (!context || width <= 0 || height <= 0) return E_INVALIDARG;
    *context = nullptr;
    Context *c = new Context();
    c->width = (UINT32)width;
    c->height = (UINT32)height;
    HRESULT hr = makeDevice(c, allowHardware != 0, info);
    if (FAILED(hr)) {
        delete c;
        return hr;
    }
    *context = c;
    return S_OK;
}

void tfd2d_release(void *context) {
    Context *c = static_cast<Context *>(context);
    if (!c) return;
    if (c->drawing) c->dc->EndDraw();
    delete c;
}

int32_t tfd2d_set_font(void *context, const uint16_t *family) {
    Context *c = static_cast<Context *>(context);
    if (!c || !family) return E_INVALIDARG;
    c->family = reinterpret_cast<const wchar_t *>(family);
    return S_OK;
}

int32_t tfd2d_set_source(void *context, int32_t slot, const uint8_t *bgra, int32_t bytesPerRow, int32_t width, int32_t height) {
    Context *c = static_cast<Context *>(context);
    if (!c || !bgra || slot < 0 || slot > 63 || width <= 0 || height <= 0) return E_INVALIDARG;
    ComPtr<ID2D1Bitmap1> &bmp = c->sources[slot];
    if (bmp) {
        const D2D1_SIZE_U s = bmp->GetPixelSize();
        if ((int32_t)s.width != width || (int32_t)s.height != height) bmp.Reset();
    }
    if (!bmp) {
        return c->dc->CreateBitmap(D2D1::SizeU(width, height), bgra, bytesPerRow, props(D2D1_BITMAP_OPTIONS_NONE, D2D1_ALPHA_MODE_IGNORE), &bmp);
    }
    const D2D1_RECT_U r = D2D1::RectU(0, 0, width, height);
    return bmp->CopyFromMemory(&r, bgra, bytesPerRow);
}

int32_t tfd2d_make_plate(void *context, int32_t slot, const TFD2DPlate *p, float *width, float *height) {
    Context *c = static_cast<Context *>(context);
    if (!c || !p || c->drawing || slot < 0 || slot > 1023) return E_INVALIDARG;
    const bool has1 = p->line1 && p->line1[0], has2 = p->line2 && p->line2[0];
    if (!has1 && !has2) return E_INVALIDARG;
    Line l1, l2;
    if (has1) TRY(measure(c, p->line1, p->size1, p->bold1 != 0, l1));
    if (has2) TRY(measure(c, p->line2, p->size2, p->bold2 != 0, l2));
    const float textW = std::max(has1 ? l1.boxWidth : 0.0f, has2 ? l2.boxWidth : 0.0f);
    const float w = textW + 2 * p->padX;
    const float h = 2 * p->padY + (has1 ? l1.boxHeight : 0) + (has1 && has2 ? p->gap : 0) + (has2 ? l2.boxHeight : 0);
    ComPtr<ID2D1Bitmap1> bmp;
    TRY(c->dc->CreateBitmap(D2D1::SizeU((UINT32)std::ceil(w), (UINT32)std::ceil(h)), nullptr, 0, props(D2D1_BITMAP_OPTIONS_TARGET), &bmp));
    c->dc->SetTarget(bmp.Get());
    c->dc->BeginDraw();
    c->dc->SetTransform(D2D1::Matrix3x2F::Identity());
    c->dc->Clear(D2D1::ColorF(0, 0, 0, 0));
    const float r = p->radius < 0 ? h / 2 : p->radius;
    c->black->SetOpacity(p->alpha);
    c->dc->FillRoundedRectangle(D2D1::RoundedRect(D2D1::RectF(0, 0, w, h), r, r), c->black.Get());
    c->black->SetOpacity(1);
    float top = p->padY;
    if (has1) {
        // Línea base a `descendente` del borde inferior de su caja.
        const float baseline = top + l1.boxHeight - l1.descent;
        c->dc->DrawTextLayout(D2D1::Point2F(p->padX, baseline - l1.layoutBaseline), l1.layout.Get(), c->white.Get());
        top += l1.boxHeight + (has2 ? p->gap : 0);
    }
    if (has2) {
        const float baseline = top + l2.boxHeight - l2.descent;
        c->dc->DrawTextLayout(D2D1::Point2F(p->padX, baseline - l2.layoutBaseline), l2.layout.Get(), c->white.Get());
    }
    HRESULT hr = c->dc->EndDraw();
    c->dc->SetTarget(c->target.Get());
    TRY(hr);
    c->plates[slot] = bmp;
    if (width) *width = w;
    if (height) *height = h;
    return S_OK;
}

int32_t tfd2d_begin(void *context, float r, float g, float b) {
    Context *c = static_cast<Context *>(context);
    if (!c || c->drawing) return E_INVALIDARG;
    c->dc->SetTarget(c->target.Get());
    c->dc->BeginDraw();
    c->drawing = true;
    c->dc->SetTransform(D2D1::Matrix3x2F::Identity());
    c->dc->Clear(D2D1::ColorF(r, g, b, 1));
    return S_OK;
}

int32_t tfd2d_box(void *context, const TFD2DBox *b) {
    Context *c = static_cast<Context *>(context);
    if (!c || !b || !c->drawing) return E_INVALIDARG;
    const D2D1_RECT_F d = D2D1::RectF(b->x, b->y, b->x + b->w, b->y + b->h);
    if (b->w <= 0 || b->h <= 0) return S_OK;
    // Lo que va por efectos se graba antes de abrir capas (no se cambia de destino con capas abiertas).
    ComPtr<ID2D1Image> content, shadow;
    if (b->blur > 0.1f) {
        ComPtr<ID2D1CommandList> list;
        TRY(c->dc->CreateCommandList(&list));
        c->dc->SetTarget(list.Get());
        HRESULT hr = drawContent(c, b, d);
        list->Close();
        c->dc->SetTarget(c->target.Get());
        TRY(hr);
        ComPtr<ID2D1Effect> clamp, soft;
        TRY(cropClamp(c, nullptr, list.Get(), d, clamp));
        TRY(blur(c, clamp.Get(), nullptr, b->blur, true, soft));
        soft->GetOutput(&content);
    }
    if (b->decorated) {
        ComPtr<ID2D1CommandList> list;
        TRY(c->dc->CreateCommandList(&list));
        c->dc->SetTarget(list.Get());
        c->black->SetOpacity(b->shadowAlpha);
        const D2D1_RECT_F s = D2D1::RectF(d.left, d.top + b->shadowOffset, d.right, d.bottom + b->shadowOffset);
        c->dc->FillRoundedRectangle(D2D1::RoundedRect(s, b->radius, b->radius), c->black.Get());
        c->black->SetOpacity(1);
        list->Close();
        c->dc->SetTarget(c->target.Get());
        ComPtr<ID2D1Effect> soft;
        TRY(blur(c, nullptr, list.Get(), b->shadowBlur, false, soft));
        soft->GetOutput(&shadow);
    }
    const bool fadeLayer = b->opacity < 1;
    if (fadeLayer) {
        c->dc->PushLayer(D2D1::LayerParameters1(D2D1::InfiniteRect(), nullptr, D2D1_ANTIALIAS_MODE_PER_PRIMITIVE,
                                                D2D1::IdentityMatrix(), std::max(0.0f, b->opacity), nullptr, D2D1_LAYER_OPTIONS1_NONE),
                         nullptr);
    }
    ComPtr<ID2D1RoundedRectangleGeometry> mask;
    if (b->decorated) {
        c->dc->DrawImage(shadow.Get(), nullptr, nullptr, D2D1_INTERPOLATION_MODE_LINEAR, D2D1_COMPOSITE_MODE_SOURCE_OVER);
        HRESULT hr = c->factory->CreateRoundedRectangleGeometry(D2D1::RoundedRect(d, b->radius, b->radius), &mask);
        if (FAILED(hr)) {
            if (fadeLayer) c->dc->PopLayer();
            return hr;
        }
        c->dc->PushLayer(D2D1::LayerParameters1(d, mask.Get(), D2D1_ANTIALIAS_MODE_PER_PRIMITIVE, D2D1::IdentityMatrix(), 1.0f, nullptr,
                                                D2D1_LAYER_OPTIONS1_NONE),
                         nullptr);
    } else {
        c->dc->PushAxisAlignedClip(d, D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
    }
    HRESULT hr = S_OK;
    if (content) {
        c->dc->DrawImage(content.Get(), nullptr, nullptr, D2D1_INTERPOLATION_MODE_LINEAR, D2D1_COMPOSITE_MODE_SOURCE_OVER);
    } else {
        hr = drawContent(c, b, d);
    }
    auto plate = c->plates.find(b->labelSlot);
    if (b->labelSlot >= 0 && plate != c->plates.end()) {
        const D2D1_SIZE_U s = plate->second->GetPixelSize();
        const D2D1_RECT_F r = D2D1::RectF(b->labelX, b->labelY, b->labelX + s.width, b->labelY + s.height);
        c->dc->DrawBitmap(plate->second.Get(), &r, 1.0f, D2D1_INTERPOLATION_MODE_LINEAR, nullptr, nullptr);
    }
    // Fundido a negro de la toma: imagen, relleno y nombre (el recuadro sigue, en negro).
    if (b->brightness < 1) fillBlack(c, d, 1 - std::max(0.0f, b->brightness));
    if (b->decorated) c->dc->PopLayer(); else c->dc->PopAxisAlignedClip();
    if (fadeLayer) c->dc->PopLayer();
    return hr;
}

int32_t tfd2d_overlay(void *context, int32_t plateSlot, float x, float y, float opacity) {
    Context *c = static_cast<Context *>(context);
    if (!c || !c->drawing) return E_INVALIDARG;
    auto plate = c->plates.find(plateSlot);
    if (plate == c->plates.end()) return E_INVALIDARG;
    const D2D1_SIZE_U s = plate->second->GetPixelSize();
    const D2D1_RECT_F r = D2D1::RectF(x, y, x + s.width, y + s.height);
    c->dc->DrawBitmap(plate->second.Get(), &r, std::min(1.0f, std::max(0.0f, opacity)), D2D1_INTERPOLATION_MODE_LINEAR, nullptr, nullptr);
    return S_OK;
}

int32_t tfd2d_end(void *context, float fade, uint8_t *out, int32_t bytesPerRow) {
    Context *c = static_cast<Context *>(context);
    if (!c || !c->drawing || !out) return E_INVALIDARG;
    if (fade < 1) fillBlack(c, D2D1::RectF(0, 0, (float)c->width, (float)c->height), 1 - std::max(0.0f, fade));
    c->drawing = false;
    TRY(c->dc->EndDraw());
    TRY(c->readback->CopyFromBitmap(nullptr, c->target.Get(), nullptr));
    D2D1_MAPPED_RECT mapped = {};
    TRY(c->readback->Map(D2D1_MAP_OPTIONS_READ, &mapped));
    const size_t row = (size_t)c->width * 4;
    for (UINT32 y = 0; y < c->height; y++) std::memcpy(out + (size_t)y * bytesPerRow, mapped.bits + (size_t)y * mapped.pitch, row);
    c->readback->Unmap();
    return S_OK;
}

} // extern "C"
#endif
