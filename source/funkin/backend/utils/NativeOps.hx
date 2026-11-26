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
