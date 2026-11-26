// Mismo script que bench-pair.cpp, pero en HScript. Si cambias uno, cambia el otro.
import flixel.FlxG;

function benchBuild(n:Int):String {
	var parts:Array<String> = [];
	for (i in 0...n) {
		if (i % 15 == 0) parts.push("fizzbuzz");
		else if (i % 3 == 0) parts.push("fizz");
		else if (i % 5 == 0) parts.push("buzz");
		else parts.push(Std.string(i));
	}
	return parts.join(",");
}

function benchWave(n:Int):Float {
	var total:Float = 0;
	for (i in 0...n) {
		total += Math.sqrt(i) * 0.5 + Math.sin(i * 0.01) + Math.cos(i * 0.02) * 0.25;
		if (i % 7 == 0) total -= Math.abs(i - 10) * 0.001;
	}
	return total;
}

function benchResult():String {
	var wave:Float = benchWave(3000);
	return benchBuild(24) + " | " + Std.string(Math.floor(wave * 100) / 100);
}

function postCreate() {
	trace("[bench][hx] " + benchResult());
}
