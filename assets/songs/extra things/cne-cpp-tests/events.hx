import funkin.backend.utils.AudioAnalyzer;
import flixel.util.FlxGradient;

var analyzer:AudioAnalyzer;
var audioPoints:Array<Array<Float>> = [];

var numberOfBars:Int = 64;
var milliseconds:Float = 50;
var exponent:Int = 2;
var startY:Float = 720;

var barColor1:Int = 0xFFaa00ff;
var barColor2:Int = 0xFF00E5FF;

var length:Float;
var secondCount:Int = 0;

var audioBarsTop:FlxTypedGroup<FlxSprite>;
var audioBarsBottom:FlxTypedGroup<FlxSprite>;
var mySquare:FlxSprite;
var isEpicPartActive:Bool = false;

function create() {
    secondCount = 0;
    audioPoints = [];

    // anailzer?
    analyzer = new AudioAnalyzer(inst);
    length = inst.length;

    var previousNum:Float = 0;
    var num:Float = 0;

    for(i in 0...length/milliseconds) {
        var seconds:Array<Float> = [];
        for(j in 0...numberOfBars) {
            num += milliseconds/numberOfBars;
            seconds.push(analyzer.analyze(previousNum, num));
            previousNum = num;
        }
        audioPoints.push(seconds);
    }

    mySquare = FlxGradient.createGradientFlxSprite(1920, 550, [0xAA000000, 0xFF000000],1, 90);
    mySquare.y = 720;
    mySquare.visible = false;
    insert(1, mySquare);

    audioBarsTop = new FlxTypedGroup();
    audioBarsTop.camera = camGame;
    audioBarsTop.visible = false;
    insert(0, audioBarsTop);

    for(i in 0...numberOfBars) {
        var currentColor = (i < numberOfBars / 2) ? barColor1 : barColor2;
        var bar:FlxSprite = new FlxSprite().makeGraphic(Std.int(FlxG.width/numberOfBars * 0.8), Std.int(FlxG.height), currentColor);
        bar.x = i * (FlxG.width/numberOfBars);
        bar.setGraphicSize(bar.width - 5, bar.height);
        bar.origin.y = 0;
        bar.y = startY;
        bar.updateHitbox();
        audioBarsTop.add(bar);
    }

    // bottom bars
    audioBarsBottom = new FlxTypedGroup();
    audioBarsBottom.camera = camGame;
    audioBarsBottom.visible = false;
    insert(0, audioBarsBottom);

    for(i in 0...numberOfBars) {
        var currentColor = (i < numberOfBars / 2) ? barColor1 : barColor2;
        var bar:FlxSprite = new FlxSprite().makeGraphic(Std.int(FlxG.width/numberOfBars * 0.8), Std.int(FlxG.height), currentColor);
        bar.x = i * (FlxG.width/numberOfBars);
        bar.setGraphicSize(bar.width - 5, bar.height);
        bar.y = FlxG.height - bar.height;
        bar.updateHitbox();
        audioBarsBottom.add(bar);
    }
}

var blackSquare:FlxSprite = new FlxSprite(0, 0);
function postCreate(){
    blackSquare.makeGraphic(FlxG.width, FlxG.height, 0xFF000000);
    blackSquare.visible = false;
    blackSquare.camera = camHUD;
    insert(0, blackSquare);
}

var whitesquare:FlxSprite = new FlxSprite(-5000, -5000);
function stepHit(curStep){
 switch (curStep) {
    case 1280:
        hideStageSprites(false);
        gf.alpha = 0;
        whitesquare.makeGraphic(10000, 10000, 0xFFFFFFFF);
        whitesquare.alpha = 1;
        whitesquare.camera = camGame;
        insert(0, whitesquare);
    for (i in [bf, dad]) {
        if (i != null) {
            i.shader = new CustomShader("RTXLighting"); 
            i.shader.satinColor = [0.5, 0.5, 0.5, 1];
            i.shader.innerShadowColor = i == bf ? hexatoRGBA(0xFFFFFFFF) : hexatoRGBA(0xFFFFFFFF);
            i.shader.innerShadowAngle = -90;
            i.shader.innerShadowDistance = 5;
            i.shader.layernumbers = 2;
            i.shader.layerseparation = 7.5;
        }
    }
    case 1408:
        blackSquareFlash(1, false);
        hideStageSprites(true);
        gf.alpha = 1;
        whitesquare.kill();
        if (bf != null) bf.shader = null;
        if (dad != null) dad.shader = null;
    case 1424:
        blackSquareFlash(1, false);
    case 1440:
        blackSquareFlash(1, false);
    case 1456:
        blackSquareFlash(1, false);
    case 1472:
        activarParteEpica(0xFFaa00ff, 0xFF00FFFF);
        blackSquareFlash(9, true);
  }
}

function beatHit(curBeat) {
    if (curBeat >= 32 && curBeat < 171) {
        bouncyHud(true);
    } else if (curBeat >= 176 && curBeat < 319) {
        bouncyHud(true);
    } else if (curBeat >= 352 && curBeat < 367 && curBeat % 4 == 0) {
        bouncyHud(true);
    } else if (curBeat >= 368 && curBeat < 395) {
        bouncyHud(true);
    } else if (curBeat >= 400 && curBeat < 559) {
        bouncyHud(true);
    } else {
        bouncyHud(false);
    }
}

var hudDirection = false;
function bouncyHud(active) {
    if (active) {
        hudDirection = !hudDirection;
        FlxTween.cancelTweensOf(camHUD);
        camHUD.angle = hudDirection ? -3 : 3;
        FlxTween.tween(camHUD, {angle: 0}, 0.25, {
            ease: FlxEase.backOut
        });
    } else {
        FlxTween.cancelTweensOf(camHUD);
        camHUD.angle = 0;
    }
}

function blackSquareFlash(time:Float = 1, invert:Bool = false) {
blackSquare.visible = true;
blackSquare.alpha = invert ? 1 : 0;
    if (invert) {
        FlxTween.tween(blackSquare, {alpha: 0}, time, {ease: FlxEase.lineal});
    } else {
        FlxTween.tween(blackSquare, {alpha: 1}, time, {ease: FlxEase.lineal});
    }
}

function hideStageSprites(show:Bool) {

    for (sprite in stage.stageSprites) {
            sprite.visible = show;
    }

}

function update(elapsed:Float) {
    if (!isEpicPartActive) return;

    if(inst.time >= length) {
        secondCount = 0;
    }
    
    if((Math.floor(inst.time/Math.pow(10, exponent)) * Math.pow(10, exponent)) % milliseconds == 0 || (Math.floor(inst.time/Math.pow(10, exponent)) * Math.pow(10, exponent)) == 0) {
        secondCount = (Math.floor(inst.time/Math.pow(10, exponent)) * Math.pow(10, exponent))/milliseconds;
    }

    if(inst.time <= length && inst != null) {
        for(i in 0...audioBarsTop.length) {
            audioBarsTop.members[i].scale.y = FlxMath.lerp(
                audioBarsTop.members[i].scale.y,
                audioPoints[secondCount][i] * 0.5,
                FlxMath.bound(elapsed * 60, 0, 1)
            );
            audioBarsTop.members[i].updateHitbox();
            audioBarsTop.members[i].y = startY;
        }

        // update bottom bars
        for(i in 0...audioBarsBottom.length) {
            audioBarsBottom.members[i].scale.y = FlxMath.lerp(
                audioBarsBottom.members[i].scale.y,
                audioPoints[secondCount][i],
                FlxMath.bound(elapsed * 60, 0, 1)
            );
            audioBarsBottom.members[i].updateHitbox();
            audioBarsBottom.members[i].y = FlxG.height - audioBarsBottom.members[i].height;
        }
    }
}

function activarParteEpica(color1, color2) {
    isEpicPartActive = true;

    // show waveforms
    if (mySquare != null) mySquare.visible = true;
    if (audioBarsTop != null) audioBarsTop.visible = true;
    if (audioBarsBottom != null) audioBarsBottom.visible = true;

    // hide gf
    if (gf != null) gf.alpha = 0;

    // hide stage sprites
    hideStageSprites(false);

    // update bar colors
    barColor1 = color1;
    barColor2 = color2;

    for (i in 0...audioBarsTop.length) {
        var currentColor = (i < numberOfBars / 2) ? barColor1 : barColor2;
        
        var topBar = audioBarsTop.members[i];
        topBar.makeGraphic(Std.int(FlxG.width/numberOfBars * 0.8), Std.int(FlxG.height), currentColor);
        topBar.updateHitbox();

        var bottomBar = audioBarsBottom.members[i];
        bottomBar.makeGraphic(Std.int(FlxG.width/numberOfBars * 0.8), Std.int(FlxG.height), currentColor);
        bottomBar.updateHitbox();
    }

    // apply shader
    for (i in [bf, dad]) {
        if (i != null) {
            i.shader = new CustomShader("RTXLighting"); 
            i.shader.satinColor = [0, 0, 0, 1];
            i.shader.innerShadowColor = i == bf ? hexatoRGBA(color2) : hexatoRGBA(color1);
            i.shader.innerShadowAngle = -90;
            i.shader.innerShadowDistance = 5;
            i.shader.layernumbers = 2;
            i.shader.layerseparation = 7.5;
        }
    }
}

function hexatoRGBA(hex:Int):Array<Float> {
    var r = ((hex >> 16) & 0xFF) / 255;
    var g = ((hex >> 8) & 0xFF) / 255;
    var b = (hex & 0xFF) / 255;
    return [r, g, b, 2];
}

function desactivarParteEpica() {
    isEpicPartActive = false;

    if (mySquare != null) mySquare.visible = false;
    if (audioBarsTop != null) audioBarsTop.visible = false;
    if (audioBarsBottom != null) audioBarsBottom.visible = false;

    // show gf
    if (gf != null) gf.alpha = 1;

    // show stage sprites
    hideStageSprites(true);

    // remove shaders
    if (bf != null) bf.shader = null;
    if (dad != null) dad.shader = null;
}