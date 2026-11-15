# Fixtures de AudioKit

Generados con ffmpeg (ver comandos en el informe de la parte P3):

    F=/opt/homebrew/bin/ffmpeg
    $F -f lavfi -i "sine=frequency=1000:duration=1.5:sample_rate=48000" -ac 1 -c:a pcm_s24le sine1k_mono_48k_24bit.wav
    $F -f lavfi -i "sine=frequency=1000:duration=1.5:sample_rate=96000" -ac 2 -c:a flac -metadata title="Tema FLAC" -metadata artist="Artista FLAC" sine1k_stereo_96k.flac
    $F -f lavfi -i "sine=frequency=1000:duration=1.5:sample_rate=44100" -ac 2 -c:a libmp3lame -b:a 64k -id3v2_version 3 -metadata title="Tema MP3" -metadata artist="Artista MP3" sine1k_stereo_44k.mp3
    $F -f lavfi -i "sine=frequency=1000:duration=0.2:sample_rate=44100" -ac 1 -c:a pcm_s16le "Artista Prueba - Tema Prueba.wav"
    head -c 2000 /dev/urandom > corrupt.wav
    : > empty.wav
