package funkin.editors.charter;

import flixel.sound.FlxSound;
import flixel.util.FlxColor;
import funkin.backend.shaders.CustomShader;
import funkin.backend.system.Conductor;
import openfl.display.BitmapData;
import openfl.display.ShaderInput;

class CharterWaveformHandler extends FlxBasic {
	public var ampsNeeded:Float = 0;
	public var ampSqrt(get, never):Int;
	public function get_ampSqrt():Int {
		var sqrt:Float = Math.sqrt(Math.floor(ampsNeeded/3));
		var ampRet:Int = Math.floor(sqrt);
		if (sqrt % 1 > 0) ampRet += 1;
		return ampRet;
	}

	public var waveDatas:Map<String, BitmapData> = [];
	public var waveShaders:Map<String, CustomShader> = [];

	public var sounds:Map<String, FlxSound> = [];
	public var analyzers:Map<String, AudioAnalyzer> = [];

	public var waveformList:Array<String> = [];

	public function new() {super(); exists = false;}

	public function generateData(name:String, sound:FlxSound):BitmapData {
		if (!sounds.exists(name)) sounds.set(name, sound);
		if (!analyzers.exists(name))
			analyzers.set(name, new AudioAnalyzer(sound));

		var analyzer:AudioAnalyzer = analyzers.get(name);

		var pixelsNeeded:Int = Math.floor(ampsNeeded/3);
		if ((ampsNeeded/3) % 1 > 0) pixelsNeeded += 1;

		var waveData:BitmapData = new BitmapData(
			ampSqrt, 1+Math.floor(pixelsNeeded/ampSqrt), true, 0xFF000000
		);

		// Se piden todas las ventanas juntas: en cpp el modulo nativo recorre el PCM
		// una sola vez, en vez de un callback de Haxe por muestra y por ventana.
		var cells:Int = waveData.width * waveData.height * 3;
		var sampleRate:Int = analyzer.data != null ? analyzer.data.sampleRate : 0;
		var startFrames:Array<Int> = [], endFrames:Array<Int> = [];

		for (gridY in 0...cells) {
			var startTime:Float = Conductor.getTimeForStep(gridY/40);
			var endTime:Float = Conductor.getTimeForStep((gridY+1)/40);

			if (sampleRate <= 0 || startTime > sound.length || endTime > sound.length) {
				// Fuera de la cancion: queda en negro, igual que antes.
				startFrames.push(0);
				endFrames.push(0);
			} else {
				startFrames.push(Math.floor(startTime * sampleRate / 1000));
				endFrames.push(Math.floor(endTime * sampleRate / 1000));
			}
		}

		var amplitudes:Array<Float> = analyzer.analyzeRanges(startFrames, endFrames);
		var cell:Int = 0;

		if (amplitudes != null && amplitudes.length >= cells * 3) {
			for (y in 0...waveData.height)
				for (x in 0...waveData.width) {
					waveData.setPixel(x, y, FlxColor.fromRGBFloat(
						CoolUtil.bound(amplitudes[cell * 3], 0, 1),
						CoolUtil.bound(amplitudes[cell * 3 + 1], 0, 1),
						CoolUtil.bound(amplitudes[cell * 3 + 2], 0, 1)));
					cell++;
				}
		}

		waveDatas.set(name, waveData);
		return waveData;
	}

	public function generateShader(name:String, sound:FlxSound):CustomShader {
		if (!waveDatas.exists(name)) generateData(name, sound);

		var waveData:BitmapData = waveDatas.get(name);

		var waveShader:CustomShader = new CustomShader(Options.charterRainbowWaveforms ? "engine/editorWaveformsRainbow" : "engine/editorWaveforms");
		waveShader.data.waveformSize.value = [waveData.width, waveData.height];
		var waveformInput:ShaderInput<BitmapData> = cast waveShader.data.waveformTexture;
		waveformInput.input = waveData;
		waveformInput.filter = NEAREST; // force it to be nearest, incase someone changed it
		waveShader.data.textureRes.value = [0, 0];
		waveShader.data.pixelOffset.value = [0];
		waveShader.data.lowDetail.value = [Options.charterLowDetailWaveforms];

		if (Options.charterRainbowWaveforms)
			waveShader.data.time.value = [0];

		waveShaders.set(name, waveShader);
		return waveShader;
	}

	public function clearWaveform(name:String) {
		waveDatas.get(name).dispose();
		waveDatas.remove(name);

		waveShaders.set(name, null);
		waveShaders.remove(name);

		analyzers.set(name, null);
		analyzers.remove(name);

		sounds.remove(name);
		waveformList.remove(name);
	}

	public function clearWaveforms() {
		for (data in waveDatas) data.dispose();
		for (shader in waveShaders) shader = null;
		for (analyzer in analyzers) analyzer = null;

		waveDatas.clear(); waveShaders.clear();
		analyzers.clear(); sounds.clear();

		waveformList = [];
	}

	public override function destroy() {
		clearWaveforms();
		super.destroy();
	}
}