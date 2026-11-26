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
};

#endif
