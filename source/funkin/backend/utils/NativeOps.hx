package funkin.backend.utils;

#if cpp
import external.ExternalNative;
#end

/**
 * Puente Haxe -> nucleo C++ nativo del motor (`external/src/native/EngineNative.cpp`).
 *
 * A diferencia de los scripts `.cpp`, esto **no** pasa por HScript: son funciones
 * C++ compiladas junto al juego, llamadas directas y sin crear objetos Haxe
 * dentro de los bucles.
 *
 * En targets sin C++ (web, hl) se usa la implementacion Haxe de abajo, asi que
 * quien llama no cambia.
 */
class NativeOps
{
	/** True si esta build lleva el modulo C++ linkeado. */
	public static var available(get, never):Bool;

	static inline function get_available():Bool
	{
		#if cpp
		return true;
		#else
		return false;
		#end
	}

	/** Version del modulo nativo, o "none" si no esta linkeado. */
	public static function version():String
	{
		#if cpp
		return ExternalNative.version();
		#else
		return "none";
		#end
	}

	/**
	 * Archivos de una carpeta (rutas relativas con '/' y ordenadas).
	 * Nativo en cpp; `sys.FileSystem` en el resto.
	 */
	public static function scanDir(path:String, recursive:Bool = true):Array<String>
	{
		#if cpp
		return ExternalNative.scanDir(path, recursive);
		#else
		var out:Array<String> = [];
		#if sys
		var root:String = path;
		while (root.length > 1 && (root.endsWith("/") || root.endsWith("\\")))
			root = root.substr(0, root.length - 1);
		walkDir(root, "", recursive, out);
		out.sort(function(a:String, b:String) return a < b ? -1 : (a > b ? 1 : 0));
		#end
		return out;
		#end
	}

	/** CRC32 del contenido de un archivo. -1 si no se puede abrir. */
	public static function crc32File(path:String):Int
	{
		#if cpp
		return ExternalNative.crc32File(path);
		#elseif sys
		var bytes:haxe.io.Bytes = null;
		try bytes = sys.io.File.getBytes(path) catch (e:Dynamic) return -1;
		if (bytes == null) return -1;

		var crc:Int = -1;
		for (i in 0...bytes.length)
		{
			crc ^= bytes.get(i);
			var bit:Int = 0;
			while (bit < 8)
			{
				crc = (crc & 1) != 0 ? (crc >>> 1) ^ 0xEDB88320 : crc >>> 1;
				bit++;
			}
		}
		return ~crc;
		#else
		return 0;
		#end
	}

	/**
	 * Amplitud de varias ventanas de un PCM ya decodificado.
	 *
	 * `startFrames`/`endFrames` son indices de frame (no de byte) y el resultado
	 * usa el mismo criterio que `AudioAnalyzer.analyze`:
	 * `(max - min) / (1 << (bitsPerSample - 1))`, una amplitud por ventana.
	 *
	 * En cpp lo resuelve `EngineNative::audioAmplitudes` en un solo recorrido, sin
	 * crear objetos Haxe dentro del bucle; en el resto de targets usa
	 * `audioAmplitudesHaxe`.
	 */
	public static function audioAmplitudes(pcm:haxe.io.Bytes, bitsPerSample:Int, channels:Int, startFrames:Array<Int>, endFrames:Array<Int>):Array<Float>
	{
		#if cpp
		return ExternalNative.audioAmplitudes(pcm.getData(), bitsPerSample, channels, startFrames, endFrames);
		#else
		return audioAmplitudesHaxe(pcm, bitsPerSample, channels, startFrames, endFrames);
		#end
	}

	/** Implementacion Haxe de `audioAmplitudes` (fallback y referencia del bench). */
	public static function audioAmplitudesHaxe(pcm:haxe.io.Bytes, bitsPerSample:Int, channels:Int, startFrames:Array<Int>, endFrames:Array<Int>):Array<Float>
	{
		var out:Array<Float> = [];
		var bytesPerSample:Int = bitsPerSample >> 3;
		var frameSize:Int = bytesPerSample * channels;
		var valid:Bool = pcm != null && bitsPerSample > 0 && (bitsPerSample & 7) == 0 && channels > 0 && frameSize > 0;
		var limit:Int = valid ? pcm.length : 0;
		// 2147483648.0 y no 1 << 31 (que en Int da negativo).
		var scale:Float = valid ? 1.0 / (bitsPerSample >= 32 ? 2147483648.0 : (1 << (bitsPerSample - 1))) : 0.0;

		for (i in 0...startFrames.length)
		{
			if (!valid || i >= endFrames.length)
			{
				out.push(0.0);
				continue;
			}

			var start:Int = startFrames[i] * frameSize;
			var end:Int = endFrames[i] * frameSize;
			if (end > limit) end = limit;

			var highest:Int = 0, lowest:Int = 0, any:Bool = false;
			var pos:Int = start;

			while (pos + bytesPerSample <= end)
			{
				var value:Int = readSample(pcm, pos, bytesPerSample);

				if (!any)
				{
					highest = lowest = value;
					any = true;
				}
				else
				{
					if (value > highest) highest = value;
					if (value < lowest) lowest = value;
				}

				pos += frameSize;
			}

			out.push(any ? (highest - lowest) * scale : 0.0);
		}

		return out;
	}

	/** Lee una muestra little endian de tamano variable. */
	static function readSample(pcm:haxe.io.Bytes, pos:Int, bytesPerSample:Int):Int
	{
		var b0:Int = pcm.get(pos);
		if (bytesPerSample == 1) return b0 > 127 ? b0 - 256 : b0;

		var b1:Int = pcm.get(pos + 1);
		if (bytesPerSample == 2)
		{
			var value:Int = b0 | (b1 << 8);
			return value > 0x7FFF ? value - 0x10000 : value;
		}

		var b2:Int = pcm.get(pos + 2);
		if (bytesPerSample == 3)
		{
			var value:Int = b0 | (b1 << 8) | (b2 << 16);
			return value > 0x7FFFFF ? value - 0x1000000 : value;
		}

		return b0 | (b1 << 8) | (b2 << 16) | (pcm.get(pos + 3) << 24);
	}

	#if sys
	static function walkDir(root:String, relative:String, recursive:Bool, out:Array<String>)
	{
		var folder:String = relative.length == 0 ? root : root + "/" + relative;
		var entries:Array<String>;

		try entries = sys.FileSystem.readDirectory(folder) catch (e:Dynamic) return;
		if (entries == null) return;

		for (entry in entries)
		{
			var child:String = relative.length == 0 ? entry : relative + "/" + entry;
			var isFolder:Bool = false;

			try isFolder = sys.FileSystem.isDirectory(folder + "/" + entry) catch (e:Dynamic) {}

			if (isFolder)
			{
				if (recursive) walkDir(root, child, recursive, out);
			}
			else out.push(child);
		}
	}
	#end
}
