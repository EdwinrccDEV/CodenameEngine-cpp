// ============================================================================
// Compara el coste de cargar un script .hx con el de compilar su equivalente
// .cpp y cargar el HScript generado. Al entrar a la cancion imprime en consola:
//
//   [bench] HScript bench-pair.hx ... -> N ms por carga
//   [bench] C++     bench-pair.cpp ... -> transpile + parse
//
// El resultado de cada script lo imprime el propio script al cargarse.
//
// Solo usa piezas que ya existen en el motor: Script.fromString (el parser),
// CPPTranspiler (el transpilador C++ -> HScript, compilado dentro del juego) y
// haxe.Timer. Ni addon ni NDLL de por medio.
// ============================================================================
import haxe.Timer;
import funkin.backend.scripting.Script;
import funkin.backend.scripting.cpp.CPPTranspiler;

// El loader solo mira scripts/ y scripts/<dificultad>, y aqui estamos en la
// carpeta anidada "extra things/cne-cpp-tests", asi que la ruta va completa.
var benchFolder:String = "songs/extra things/cne-cpp-tests/scripts/";
/** Rondas cronometradas. */
var benchRounds:Int = 3;
/** Cargas por ronda: se promedian para quitar ruido del reloj. */
var benchBatch:Int = 5;

function postCreate() {
	var hxPath:String = benchFolder + "bench-pair.hx";
	var cppPath:String = benchFolder + "bench-pair.cpp";
	if (!Assets.exists(hxPath) || !Assets.exists(cppPath)) {
		trace("[bench] no encuentro bench-pair.hx / bench-pair.cpp");
		return;
	}
	try {
		benchCompare(Assets.getText(hxPath), Assets.getText(cppPath), hxPath, cppPath);
	} catch (e:Dynamic) {
		trace("[bench] error en el benchmark: " + Std.string(e));
	}
}

/**
 * Convierte el texto en un Script, que es justo lo que cuesta al abrir la
 * cancion: el parser del motor. El load() posterior se hace igual en los dos
 * caminos, asi que se deja fuera de la medida.
 *
 * Cada carga usa un nombre de sonda distinto y que no existe en disco, para que
 * el motor no pueda reutilizar nada por nombre en ninguna de las dos rutas.
 */
function benchParse(code:String, probeName:String) {
	return Script.fromString(code, probeName);
}

function benchCompare(hxSource:String, cppSource:String, hxName:String, cppName:String) {
	// Calentamiento: la primera carga paga resolucion de clases y demas.
	benchParse(hxSource, "bench/warmup_hx.hx");
	var generated:String = CPPTranspiler.compile(cppSource, null);
	benchParse(generated, "bench/warmup_cpp.hx");

	var hxTotal:Float = 0;
	var transpileTotal:Float = 0;
	var cppParseTotal:Float = 0;

	// Intercalado: en cada vuelta se mide una carga .hx, una transpilacion y una
	// carga del HScript generado, asi el ruido del reloj y del recolector cae
	// igual en los dos caminos.
	var r = 0;
	while (r < benchRounds) {
		var i = 0;
		while (i < benchBatch) {
			var t:Float = Timer.stamp();
			benchParse(hxSource, "bench/a_" + r + "_" + i + ".hx");
			hxTotal += Timer.stamp() - t;

			var t2:Float = Timer.stamp();
			generated = CPPTranspiler.compile(cppSource, null);
			transpileTotal += Timer.stamp() - t2;

			var t3:Float = Timer.stamp();
			benchParse(generated, "bench/b_" + r + "_" + i + ".hx");
			cppParseTotal += Timer.stamp() - t3;
			i++;
		}
		r++;
	}

	var loads:Int = benchRounds * benchBatch;
	var hxAvg:Float = hxTotal * 1000 / loads;
	var transpileAvg:Float = transpileTotal * 1000 / loads;
	var parseAvg:Float = cppParseTotal * 1000 / loads;
	var cppAvg:Float = transpileAvg + parseAvg;

	trace("[bench] HScript " + benchShort(hxName) + ": " + benchLines(hxSource) + " lineas, " + hxSource.length + " chars -> " + benchNum(hxAvg) + " ms por carga");
	trace("[bench] C++     " + benchShort(cppName) + ": " + benchLines(cppSource) + " lineas, " + cppSource.length + " chars -> transpile " + benchNum(transpileAvg) + " + parse " + benchNum(parseAvg) + " = " + benchNum(cppAvg) + " ms por carga");
	trace("[bench] generado: " + benchLines(generated) + " lineas, " + generated.length + " chars (transpilador del motor)");
	trace("[bench] coste C++/HScript: " + benchNum(cppAvg / (hxAvg <= 0 ? 1 : hxAvg)) + "x | " + loads + " cargas por modo (" + benchRounds + " rondas x " + benchBatch + ", intercaladas)");

	// La comparacion de comportamiento la dan los propios scripts: cada uno
	// imprime su resultado al cargarse, asi que las lineas [bench][hx] y
	// [bench][cpp] tienen que salir identicas.
	trace("[bench] compara las lineas [bench][hx] y [bench][cpp]: deben ser iguales");
}

/** Solo el nombre del archivo, para las lineas del reporte. */
function benchShort(path:String):String {
	var i = path.lastIndexOf("/");
	return i < 0 ? path : path.substr(i + 1);
}

function benchLines(text:String):Int {
	if (text == null || text.length == 0) return 0;
	return text.split("\n").length;
}

function benchNum(value:Float):String {
	return Std.string(Math.round(value * 100) / 100);
}
