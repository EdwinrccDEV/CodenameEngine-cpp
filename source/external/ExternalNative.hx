package external;

#if cpp
/**
 * Bindings al nucleo C++ nativo del motor (source/external/src/native/EngineNative.cpp).
 *
 * `LinkerMacro.xml` inyecta `external_native.xml` en el build de hxcpp, que
 * compila el .cpp junto al juego e incluye la cabecera. No hay NDLL de por
 * medio: estas funciones son C++ normal enlazado en el mismo ejecutable.
 *
 * El .xml se resuelve relativo a este archivo, por eso vive en esta carpeta.
 */
@:keep
@:build(external.LinkerMacro.xml('external_native.xml'))
@:cppFileCode('#include "EngineNative.h"')
class ExternalNative
{
	/** Version del modulo nativo. */
	public static function version():String
	{
		return untyped __cpp__("EngineNative::version()");
	}

	/** Archivos de una carpeta, relativos a `path`, con '/' y ordenados. */
	public static function scanDir(path:String, recursive:Bool):Array<String>
	{
		return untyped __cpp__("EngineNative::scanDir({0}, {1})", path, recursive);
	}

	/** CRC32 del contenido de un archivo (-1 si no se puede abrir). */
	public static function crc32File(path:String):Int
	{
		return untyped __cpp__("EngineNative::crc32File({0})", path);
	}

	/**
	 * Amplitudes de ventanas sobre un PCM ya decodificado.
	 * `startFrames`/`endFrames` son indices de frame, no de byte.
	 */
	public static function audioAmplitudes(pcm:haxe.io.Bytes, bitsPerSample:Int, channels:Int, startFrames:Array<Int>, endFrames:Array<Int>):Array<Float>
	{
		return untyped __cpp__("EngineNative::audioAmplitudes({0}, {1}, {2}, {3}, {4})", pcm, bitsPerSample, channels, startFrames, endFrames);
	}
}
#end
