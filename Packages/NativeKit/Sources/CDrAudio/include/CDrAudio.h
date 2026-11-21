// Cabecera paraguas del módulo CDrAudio: lectura de WAV/AIFF, FLAC y MP3 y escritura de WAV con dr_wav,
// dr_flac y dr_mp3 (dominio público / MIT-0, ver LICENSE). Las rutas van en UTF-8; en Windows se pasan a
// UTF-16 y se abren con las variantes `_w`, así que valen rutas no ASCII.
#ifndef CDRAUDIO_H
#define CDRAUDIO_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Contenedor reconocido por los primeros bytes del fichero.
typedef enum {
    TFAUDIO_WAV = 0,   ///< RIFF, RF64, Wave64 o AIFF (dr_wav)
    TFAUDIO_FLAC = 1,  ///< dr_flac
    TFAUDIO_MP3 = 2    ///< dr_mp3
} tfaudio_kind;

typedef struct tfaudio_reader tfaudio_reader;

/// Abre para leer. NULL si no se reconoce o no se puede decodificar.
tfaudio_reader *tfaudio_open(const char *pathUTF8);
void tfaudio_close(tfaudio_reader *r);
int tfaudio_kind_of(const tfaudio_reader *r);
uint32_t tfaudio_sample_rate(const tfaudio_reader *r);
uint32_t tfaudio_channels(const tfaudio_reader *r);
/// Longitud en fotogramas (en MP3 se calcula decodificando una vez, como `AVAudioFile.length`).
uint64_t tfaudio_frame_count(const tfaudio_reader *r);
/// Lee hasta `frames` fotogramas entrelazados en float [-1, 1]. Devuelve los leídos (0 al final).
uint64_t tfaudio_read_f32(tfaudio_reader *r, float *interleaved, uint64_t frames);
/// Posiciona en el fotograma `frame`. 1 si va bien.
int tfaudio_seek(tfaudio_reader *r, uint64_t frame);

typedef struct tfaudio_writer tfaudio_writer;

/// Crea un WAV. `bits`: 16 o 24 (PCM entero) o 32 (IEEE float). NULL si falla.
tfaudio_writer *tfaudio_writer_open(const char *pathUTF8, uint32_t sampleRate, uint32_t channels, int bits);
/// Escribe fotogramas entrelazados float. Al pasar a entero redondea a la mitad lejos de cero y recorta a
/// [-2^(b-1), 2^(b-1) - 1], como el conversor de Core Audio que usa `AVAudioFile`. Devuelve los escritos.
uint64_t tfaudio_writer_write_f32(tfaudio_writer *w, const float *interleaved, uint64_t frames);
/// Cierra y completa la cabecera. 1 si va bien.
int tfaudio_writer_close(tfaudio_writer *w);

#ifdef __cplusplus
}
#endif
#endif
