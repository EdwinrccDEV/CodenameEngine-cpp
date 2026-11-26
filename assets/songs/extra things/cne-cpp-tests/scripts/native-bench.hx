// ============================================================================
// Mide el nucleo C++ nativo contra la implementacion Haxe del mismo trabajo.
//
// No mide scripts: mide funciones C++ compiladas junto al juego
// (external/src/native/EngineNative.cpp) llamadas desde Haxe sin interprete.
//
// Al entrar a la cancion imprime:
//
//   [native] EngineNative <version> linkeado
//   [native] scanDir <carpeta>: nativo N archivos, haxe N archivos
//   [native] escaneo: nativo X ms | haxe Y ms | Zx
//   [native] crc32 <archivo>: <ms> ms (<MB/s>) -> <crc>
// ============================================================================
import funkin.backend.utils.NativeOps;
import sys.FileSystem;

/** Carpeta a escanear, relativa a la raiz del juego. */
var nativeTarget:String = "assets/images";
/** Vueltas cronometradas (se promedian). */
var nativeRounds:Int = 3;

function postCreate() {
	if (!NativeOps.available) {
		trace("[native] este build no lleva el modulo C++ linkeado");
		return;
	}

	trace("[native] EngineNative " + NativeOps.version() + " linkeado");

	if (!FileSystem.exists(nativeTarget)) {
		trace("[native] no existe la carpeta " + nativeTarget);
		return;
	}

	var nativeFiles:Array<String> = NativeOps.scanDir(nativeTarget, true);
	var haxeFiles:Array<String> = nativeScanHaxe(nativeTarget, true);

	trace("[native] scanDir " + nativeTarget + ": nativo " + nativeFiles.length + " archivos, haxe " + haxeFiles.length
		+ (nativeFiles.length == haxeFiles.length ? " (coinciden)" : " (DIFERENCIAS!)"));

	var nativeTotal:Float = 0;
	var haxeTotal:Float = 0;

	for (r in 0...nativeRounds) {
		var t:Float = haxe.Timer.stamp();
		nativeFiles = NativeOps.scanDir(nativeTarget, true);
		nativeTotal += haxe.Timer.stamp() - t;

		t = haxe.Timer.stamp();
		haxeFiles = nativeScanHaxe(nativeTarget, true);
		haxeTotal += haxe.Timer.stamp() - t;
	}

	var nativeAvg:Float = nativeTotal * 1000 / nativeRounds;
	var haxeAvg:Float = haxeTotal * 1000 / nativeRounds;

	trace("[native] escaneo: nativo " + nativeMs(nativeAvg) + " ms | haxe " + nativeMs(haxeAvg) + " ms | "
		+ nativeMs(haxeAvg / (nativeAvg <= 0 ? 1 : nativeAvg)) + "x");

	nativeBenchCrc("assets/songs/extra things/cne-cpp-tests/song/inst.ogg");

	try nativeBenchWaveform()
	catch (e:Dynamic) trace("[native] waveform: no se pudo medir (" + Std.string(e) + ")");
}

function nativeBenchCrc(path:String) {
	if (!FileSystem.exists(path)) {
		trace("[native] no existe " + path);
		return;
	}

	var size:Float = FileSystem.stat(path).size;
	var t:Float = haxe.Timer.stamp();
	var crc:Int = NativeOps.crc32File(path);
	var ms:Float = (haxe.Timer.stamp() - t) * 1000;
	var mbps:Float = ms <= 0 ? 0 : (size / 1048576) / (ms / 1000);

	trace("[native] crc32 " + nativeMs(size / 1048576) + " MB: " + nativeMs(ms) + " ms ("
		+ nativeMs(mbps) + " MB/s) -> " + crc);
}

/**
 * Amplitudes de waveform: modulo nativo vs implementacion Haxe, sobre el mismo
 * PCM sintetico (2 s, 16 bits, estereo, 44.1 kHz).
 * El editor de charts usa esto para dibujar las waveforms.
 */
function nativeBenchWaveform() {
	var sampleRate:Int = 44100;
	var frames:Int = sampleRate * 2;
	var channels:Int = 2;
	var pcm:haxe.io.Bytes = haxe.io.Bytes.alloc(frames * channels * 2);

	for (i in 0...frames) {
		var value:Int = Math.round(Math.sin(i * 0.02) * 16000);
		var low:Int = value & 0xFF;
		var high:Int = (value >> 8) & 0xFF;

		for (c in 0...channels) {
			pcm.set((i * channels + c) * 2, low);
			pcm.set((i * channels + c) * 2 + 1, high);
		}
	}

	// Ventanas de 1 ms, como las columnas del grid del editor.
	var windowFrames:Int = Std.int(sampleRate / 1000);
	var count:Int = Std.int(frames / windowFrames);
	var starts:Array<Int> = [], ends:Array<Int> = [];

	for (i in 0...count) {
		starts.push(i * windowFrames);
		ends.push((i + 1) * windowFrames);
	}

	var rounds:Int = 20;
	var nativeTotal:Float = 0;
	var haxeTotal:Float = 0;
	var nativeAmps:Array<Float> = null;
	var haxeAmps:Array<Float> = null;

	for (r in 0...rounds) {
		var t:Float = haxe.Timer.stamp();
		nativeAmps = NativeOps.audioAmplitudes(pcm, 16, channels, starts, ends);
		nativeTotal += haxe.Timer.stamp() - t;

		t = haxe.Timer.stamp();
		haxeAmps = NativeOps.audioAmplitudesHaxe(pcm, 16, channels, starts, ends);
		haxeTotal += haxe.Timer.stamp() - t;
	}

	var mismatch:Int = 0;
	for (i in 0...nativeAmps.length)
		if (Math.abs(nativeAmps[i] - haxeAmps[i]) > 0.0001) mismatch++;

	var nativeAvg:Float = nativeTotal * 1000 / rounds;
	var haxeAvg:Float = haxeTotal * 1000 / rounds;

	trace("[native] waveform " + count + " ventanas: nativo " + nativeMs(nativeAvg) + " ms | haxe "
		+ nativeMs(haxeAvg) + " ms | " + nativeMs(haxeAvg / (nativeAvg <= 0 ? 1 : nativeAvg)) + "x | "
		+ (mismatch == 0 ? "amplitudes coinciden" : mismatch + " DIFERENCIAS"));
}

/** La misma implementacion Haxe que usa NativeOps cuando no hay C++. */
function nativeScanHaxe(root:String, recursive:Bool):Array<String> {
	var out:Array<String> = [];
	nativeWalk(root, "", recursive, out);
	out.sort(function(a:String, b:String) return a < b ? -1 : (a > b ? 1 : 0));
	return out;
}

function nativeWalk(root:String, relative:String, recursive:Bool, out:Array<String>) {
	var folder:String = relative.length == 0 ? root : root + "/" + relative;
	var entries:Array<String>;

	try entries = FileSystem.readDirectory(folder) catch (e:Dynamic) return;
	if (entries == null) return;

	for (entry in entries) {
		var child:String = relative.length == 0 ? entry : relative + "/" + entry;
		var isFolder:Bool = false;

		try isFolder = FileSystem.isDirectory(folder + "/" + entry) catch (e:Dynamic) {}

		if (isFolder) {
			if (recursive) nativeWalk(root, child, recursive, out);
		}
		else out.push(child);
	}
}

function nativeMs(value:Float):String {
	return Std.string(Math.round(value * 100) / 100);
}
