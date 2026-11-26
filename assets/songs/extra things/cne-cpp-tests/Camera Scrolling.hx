public var offsetSing = 60;
public var isScroll = true;
public var isForcedCam = false;


function postUpdate(elapsed) {
    
  var char = strumLines.members[curCameraTarget].characters[0];
     
  if (isScroll != true) return;

  switch(char.getAnimName()) {
             case "singLEFT":    
                 doScrollStuff(-offsetSing, 0, 1);  
             case "singDOWN":
                      doScrollStuff(0, offsetSing, 0); 
             case "singUP":
                    doScrollStuff(0, -offsetSing, 0);  
             case "singRIGHT":
                    doScrollStuff(offsetSing, 0, -1);     
             case "idle", "singLEFTmiss", "singDOWNmiss", "singUPmiss", "singRIGHTmiss":
                    doScrollStuff(0, 0, 0);              
             }

}

function doScrollStuff(x, y, angle)
 {
  FlxG.camera.targetOffset.set(x, y);
  FlxG.camera.angle = FlxMath.lerp(FlxG.camera.angle, angle, camera.followLerp * offsetSing / 30);
}

function onCameraMove(e) if (isForcedCam) e.cancelled = true; else e.cancelled = false;