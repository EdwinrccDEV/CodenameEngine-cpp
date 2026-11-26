package funkin.backend.scripting;

import funkin.backend.scripting.cpp.CPPTranspiler;
import haxe.io.Path;

/**
 * Script written in the C++ subset the engine understands.
 *
 * The engine transpiles the file to HScript itself and then runs it through the
 * normal HScript interpreter, so a `.cpp` file can be dropped anywhere a `.hx`
 * file is loaded (song scripts, global scripts, stage/character scripts...) and
 * receives the same callbacks.
 *
 * Being part of the engine, this needs no addon and no NDLL: the transpiler is
 * compiled together with the game, so the only cost is the transpilation.
 *
 * Un `#include "algo.hpp"` que exista junto al script se lee del disco y se
 * procesa como cabecera local; los `#include` de paquetes del motor
 * (`funkin/game/PlayState.hpp`, `flixel/...`) se convierten en `import`.
 */
class CPPScript extends HScript {
	/** Tiempo (ms) que tardo la ultima transpilacion. */
	public static var lastTranspileMs:Float = 0;

	/** Suma de todas las transpilaciones desde que arranco el juego. */
	public static var totalTranspileMs:Float = 0;

	/** HScript generado por la ultima carga (util para depurar). */
	public var generated:String = null;

	override public function loadFromString(code:String) {
		if (code != null && code.length > 0) {
			var start = haxe.Timer.stamp();
			try {
				code = CPPTranspiler.compile(code, makeResolver(rawPath != null ? rawPath : path));
			} catch (e:Dynamic) {
				Logs.error('Failed to transpile $fileName: ' + Std.string(e));
			}
			lastTranspileMs = (haxe.Timer.stamp() - start) * 1000;
			totalTranspileMs += lastTranspileMs;
			generated = code;
		}
		return super.loadFromString(code);
	}

	/**
	 * Resuelve un `#include` local como lo haria el compilador: primero junto al
	 * script, luego como ruta de assets. Si la cabecera no aparece devuelve null
	 * y el transpilador deja la directiva tal cual.
	 */
	static function makeResolver(scriptPath:String):String->String {
		var dir = scriptPath == null ? null : Path.directory(scriptPath);
		return function(include:String):String {
			if (include == null || include.length == 0) return null;
			var rel = StringTools.replace(include, "\\", "/");
			var candidates:Array<String> = [];
			if (dir != null && dir.length > 0) candidates.push('$dir/$rel');
			candidates.push(rel);
			for (candidate in candidates) {
				try {
					if (Assets.exists(candidate)) return Assets.getText(candidate);
				} catch (e:Dynamic) {}
			}
			return null;
		};
	}
}
