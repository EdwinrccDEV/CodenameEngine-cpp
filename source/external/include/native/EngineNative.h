#ifndef ENGINE_NATIVE_H
#define ENGINE_NATIVE_H

#include <hxcpp.h>

/**
 * Nucleo C++ nativo del motor.
 *
 * No es un NDLL: este archivo y su .cpp se compilan junto al juego (ver
 * external_native.xml y funkin.backend.utils.NativeOps), asi que las llamadas
 * son directas y sin marshalling. Aca van las operaciones que en Haxe pagan
 * allocaciones del GC por elemento.
 *
 * Reglas para lo que se agregue aca:
 *  - Entradas y salidas primitivas, String, Array<String> o buffers.
 *  - Nunca guardar referencias a objetos Haxe entre llamadas.
 *  - Los bucles grandes no deben crear objetos Haxe dentro.
 */
class EngineNative
{
public:
	/** Version del modulo, para comprobar desde el juego que el C++ esta linkeado. */
	static ::String version();

	/**
	 * Lista los archivos de una carpeta, recursivo o no.
	 * Devuelve rutas relativas a `path`, con '/' como separador y ordenadas.
	 * Devuelve un Array vacio si la carpeta no existe.
	 */
	static ::Array< ::String> scanDir(::String path, bool recursive);

	/** CRC32 del contenido de un archivo. Devuelve -1 si no se puede abrir. */
	static int crc32File(::String path);

	/**
	 * Amplitud de varias ventanas de un PCM ya decodificado.
	 *
	 * `pcm` es el buffer crudo (16/8/24/32 bits, little endian, entrelazado) y
	 * llega como `haxe.io.BytesData` (`::Array<unsigned char>`): el grupo
	 * `external-native` no tiene en el include path los headers que hxcpp genera
	 * (por eso no se puede declarar `::haxe::io::Bytes` aca),
	 * `startFrames`/`endFrames` son indices de frame (no de byte). Devuelve una
	 * amplitud por ventana, en el mismo orden, con el mismo criterio que
	 * `AudioAnalyzer.analyze`: (max - min) / (1 << (bits-1)).
	 * Una ventana sin muestras (o un PCM invalido) devuelve 0.
	 */
	static ::Array<Float> audioAmplitudes(::Array<unsigned char> pcm, int bitsPerSample, int channels,
		::Array<int> startFrames, ::Array<int> endFrames);
};

#endif
