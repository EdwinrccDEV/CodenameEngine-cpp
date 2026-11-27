package funkin.game;

import flixel.math.FlxPoint;
import flixel.math.FlxAngle;
import flixel.math.FlxRect;
import flixel.graphics.frames.FlxFrame;
import flixel.graphics.frames.FlxFramesCollection;
import funkin.backend.chart.ChartData;
import funkin.backend.scripting.events.note.NoteCreationEvent;
import funkin.backend.system.Conductor;

using StringTools;

@:allow(funkin.game.PlayState)
class Note extends FlxSprite
{
	public var extra:Map<String, Dynamic> = [];

	public var strumTime:Float = 0;

	public var mustPress(get, never):Bool;
	public var strumLine(default, set):StrumLine;
	private function set_strumLine(strLine:StrumLine) {
		if (this.strumLine != null) {
			if (this.strumLine.notes != null)
				this.strumLine.notes.remove(this, true);
			strLine.notes.add(this);
			strLine.notes.sortNotes();
		}
		return strumLine = strLine;
	}

	private inline function get_mustPress():Bool {
		return false;
	}
	public var noteData:Int = 0;
	public var canBeHit:Bool = false;
	public var tooLate:Bool = false;
	public var wasGoodHit:Bool = false;

	/**
	 * Whenever that note should be avoided by Botplay.
	 */
	public var avoid:Bool = false;

	/**
	 * The note that comes before this one (sustain and not)
	 */
	public var prevNote:Note;
	/**
	 * The note that comes after this one (sustain and not)
	 */
	public var nextNote:Note;
	/**
	 * The next sustain after this one
	 */
	public var nextSustain:Note;

	/**
	 * The parent of the sustain.
	 * 
	 * If this note is not sustain, this will be null.
	 */
	public var sustainParent:Null<Note>;

	/**
	 * Number of active sustain pieces attached to this note
	 * 
	 * Increases by 1 every time a hold piece is initialized.
	 * 
	 * Decreases by 1 every time a hold piece gets destroyed.
	 */
	public var tailCount:Int = 0;

	/**
	 * Name of the splash.
	 */
	public var splash:String = "default";

	public var strumID(get, never):Int;
	private function get_strumID() {
		return if (noteData < 0) 0; else noteData % strumLine.members.length;
	}

	public var sustainLength:Float = 0;
	public var isSustainNote:Bool = false;
	public var noSustainClip:Bool = false;
	public var flipSustain:Bool = true;

	public var noteTypeID:Int = 0;

	// TO APPLY THOSE ON A SINGLE NOTE
	public var scrollSpeed:Null<Float> = null;
	public var noteAngle:Null<Float> = null;

	public var copyStrumAngle:Bool = true;
	public var updateNotesPosX:Bool = true;
	public var updateNotesPosY:Bool = true;
	public var updateFlipY:Bool = true;

	public var noteType(get, never):String;

	@:dox(hide) public var __strumCameras:Array<FlxCamera> = null;
	@:dox(hide) public var __strum:Strum = null;
	@:dox(hide) public var __noteAngle:Float = 0;

	@:dox(hide) private var __lastSustainClipT:Float = -1.0;

	private function get_noteType() {
		if (PlayState.instance == null) return null;
		return PlayState.instance.getNoteType(noteTypeID);
	}

	public static var swagWidth:Float = 160 * 0.7; // TODO: remove this

	private static var __customNoteTypeExists:Map<String, Bool> = [];

	/**
	 * Indices de frames por atlas + prefijo.
	 *
	 * `animation.addByPrefix` recorre TODO el atlas de la nota (y arma arrays nuevos)
	 * cada vez que se crea una nota; en canciones de miles de notas eso se paga al
	 * cargar. Como los indices solo dependen del atlas, se calculan una vez.
	 */
	private static var __animFrameIndices:Map<FlxFramesCollection, Map<String, Array<Int>>> = [];
	private static var __animFrameIndicesCount:Int = 0;

	private static function __prefixFrameIndices(frameSet:FlxFramesCollection, prefix:String):Array<Int> {
		var cache:Map<String, Array<Int>> = __animFrameIndices.get(frameSet);
		if (cache == null) {
			// tope para no retener atlases para siempre si un mod carga muchisimos tipos de nota
			if (__animFrameIndicesCount >= 32) {
				__animFrameIndices.clear();
				__animFrameIndicesCount = 0;
			}
			cache = [];
			__animFrameIndices.set(frameSet, cache);
			__animFrameIndicesCount++;
		}

		var indices:Array<Int> = cache.get(prefix);
		if (indices != null) return indices;

		indices = [];
		var all:Array<FlxFrame> = frameSet.frames;
		for (i in 0...all.length) {
			var frame:FlxFrame = all[i];
			if (frame.name != null && frame.name.startsWith(prefix)) indices.push(i);
		}
		cache.set(prefix, indices);
		return indices;
	}

	/** Agrega la animacion `name` (frames que empiezan con `prefix`), reusando los indices cacheados. */
	private static function __addAnim(sprite:FlxSprite, name:String, frameSet:FlxFramesCollection, prefix:String):Bool {
		var indices:Array<Int> = __prefixFrameIndices(frameSet, prefix);
		if (indices.length == 0) return false;
		sprite.animation.add(name, indices, 30, true);
		return true;
	}

	public var animSuffix:String = null;

	// Deprecated?
	@:dox(hide) public var tripTimer:Float = 0; // ranges from 0 to 1

	private static function customTypePathExists(path:String) {
		if (__customNoteTypeExists.exists(path))
			return __customNoteTypeExists[path];
		return __customNoteTypeExists[path] = Assets.exists(path);
	}

	static var DEFAULT_FIELDS:Array<String> = ["time", "id", "type", "sLen"];

	public function new(strumLine:StrumLine, noteData:ChartNote, sustain:Bool = false, sustainLength:Float = 0, sustainOffset:Float = 0, ?prev:Note) {
		super();

		moves = false;

		if(prev != null)
			this.prevNote = prev;
		else
			this.prevNote = strumLine.notes.members.last();

		if (this.prevNote != null) this.prevNote.nextNote = this;
		this.noteTypeID = noteData.type.getDefault(0);
		this.isSustainNote = sustain;
		this.sustainLength = sustainLength;
		this.strumLine = strumLine;
		for(field in Reflect.fields(noteData)) if(!DEFAULT_FIELDS.contains(field))
			this.extra.set(field, Reflect.field(noteData, field));

		// work around to set the `sustainParent`
		if (isSustainNote)
			sustainParent = prevNote.isSustainNote ? prevNote.sustainParent : prevNote;

		x += 50;
		// MAKE SURE ITS DEFINITELY OFF SCREEN?
		y -= 2000;

		this.strumTime = noteData.time.getDefault(0) + sustainOffset;
		this.noteData = noteData.id.getDefault(0);

		var customType = this.noteType != null ? Paths.image('game/notes/${this.noteType}') : null;
		var event = EventManager.get(NoteCreationEvent).recycle(this, strumID, this.noteType, noteTypeID, (PlayState.instance != null) ? (PlayState.instance.strumLines.members.indexOf(strumLine)) : strumLine.ID, mustPress,
			(this.noteType != null && customTypePathExists(customType)) ? 'game/notes/${this.noteType}' : 'game/notes/default', @:privateAccess strumLine.strumScale * Flags.DEFAULT_NOTE_SCALE, animSuffix);

		if (PlayState.instance != null)
			event = PlayState.instance.gameAndCharsEvent("onNoteCreation", event);

		this.animSuffix = event.animSuffix;
		if (!event.cancelled) {
			switch (event.noteType)
			{
				// case "My Custom Note Type": // hardcoding note types
				default:
					frames = Paths.getFrames(event.noteSprite);

					switch(event.strumID % 4) {
						case 0:
							__addAnim(this, 'scroll', frames, 'purple0');
							__addAnim(this, 'hold', frames, 'purple hold piece');
							if (!__addAnim(this, 'holdend', frames, 'pruple end hold'))
								__addAnim(this, 'holdend', frames, 'purple hold end');
						case 1:
							__addAnim(this, 'scroll', frames, 'blue0');
							__addAnim(this, 'hold', frames, 'blue hold piece');
							__addAnim(this, 'holdend', frames, 'blue hold end');
						case 2:
							__addAnim(this, 'scroll', frames, 'green0');
							__addAnim(this, 'hold', frames, 'green hold piece');
							__addAnim(this, 'holdend', frames, 'green hold end');
						case 3:
							__addAnim(this, 'scroll', frames, 'red0');
							__addAnim(this, 'hold', frames, 'red hold piece');
							__addAnim(this, 'holdend', frames, 'red hold end');
					}

					scale.set(event.noteScale, event.noteScale);
					antialiasing = true;
			}
		}

		// Un solo updateHitbox por nota: en los pedazos de sustain el hitbox se
		// recalculaba justo antes de `play('holdend')` y otra vez despues, con el
		// mismo frame, asi que solo se hace el segundo (el que ya usa el frame final).
		if (isSustainNote && prevNote != null)
		{
			alpha = 0.6;
			animation.play('holdend');

			updateHitbox();

			if (prevNote.isSustainNote)
			{
				prevNote.nextSustain = this;
				prevNote.animation.play('hold');
			}
		} else {
			updateHitbox();
			animation.play("scroll");
		}

		if (PlayState.instance != null) {
			PlayState.instance.splashHandler.getSplashGroup(splash);
			PlayState.instance.gameAndCharsEvent("onPostNoteCreation", event);
		}
	}

	public var lastScrollSpeed:Null<Float> = null;
	public var gapFix:SingleOrFloat = 0;
	public var useAntialiasingFix(get, set):Bool;

	inline function set_useAntialiasingFix(v:Bool) {
		if(v != useAntialiasingFix) {
			gapFix = v ? 1 : 0;
		}
		return v;
	}
	inline function get_useAntialiasingFix() {
		return gapFix > 0;
	}

	/**
	 * Whenever the position of the note should be relative to the strum position or not.
	 * For example, if this is true, a note at the position 0; 0 will be on the strum, instead of at the top left of the screen.
	 */
	public var strumRelativePos:Bool = true;

	@:dox(hide) static var __lastAngle:Float = Math.NaN;
	@:dox(hide) static var __lastAngleSin:Float = 0;
	@:dox(hide) static var __lastAngleCos:Float = 0;
	@:dox(hide) static var __lastStrumW:Float = Math.NaN;
	@:dox(hide) static var __lastStrumH:Float = Math.NaN;
	@:dox(hide) static var __lastStrumHalfW:Float = 0;
	@:dox(hide) static var __lastStrumHalfH:Float = 0;

	override function draw() {
		@:privateAccess var oldDefaultCameras = FlxCamera._defaultCameras;
		@:privateAccess if (__strumCameras != null) FlxCamera._defaultCameras = __strumCameras;

		var negativeScroll = isSustainNote && strumRelativePos && lastScrollSpeed < 0;
		if (negativeScroll) y -= height;
		if (__strum != null && strumRelativePos) {
			final originalX = x;
			final originalY = y;

			if (__noteAngle != __lastAngle) {
				__lastAngle = __noteAngle;
				final result = FlxMath.fastSinCos((__noteAngle + 90) * FlxAngle.TO_RAD);
				__lastAngleSin = result.sin;
				__lastAngleCos = result.cos;
			}

			if (__strum.width != __lastStrumW || __strum.height != __lastStrumH) {
				__lastStrumW = __strum.width;
				__lastStrumH = __strum.height;
				__lastStrumHalfW = __strum.width * 0.5;
				__lastStrumHalfH = __strum.height * 0.5;
			}

			x = -origin.x + offset.x + (originalY * __lastAngleCos + originalX * __lastAngleSin) + __strum.x + __lastStrumHalfW;
			y = -origin.y + offset.y + (originalY * __lastAngleSin - originalX * __lastAngleCos) + __strum.y + __lastStrumHalfH;
			super.draw();
			x = originalX;
			y = originalY;
		} else {
			super.draw();
		}
		if (negativeScroll) y += height;

		@:privateAccess FlxCamera._defaultCameras = oldDefaultCameras;
	}

	var __lastDownscrollCam:Bool = false;
	var __lastX:Float = 0;

	@:noCompletion @:dox(hide) override function isOnScreen(?camera:FlxCamera):Bool {
		var downscrollCam:Bool = ((camera is HudCamera) ? (cast camera:HudCamera).downscroll : false);
		if (updateFlipY) {
			flipY = (isSustainNote && flipSustain) && (downscrollCam != (lastScrollSpeed < 0));
		}
		if (downscrollCam == __lastDownscrollCam)
			return super.isOnScreen(camera);
		else
			__lastX = x;

		if (downscrollCam && __strum != null && __strum.updateNotesPosX && updateNotesPosX) {
			x = -x + 2 * (__strum.x - origin.x + offset.x) + __strum.width;
		}
		final isOnScreen = super.isOnScreen(camera);
		return isOnScreen;
	}

	override function drawComplex(camera:FlxCamera):Void {
		super.drawComplex(camera);

		if (__lastDownscrollCam) {
			__lastDownscrollCam = false;
			x = __lastX;
		}
	}

	public function isOnScreenOriginal(?camera:FlxCamera):Bool {
    	return super.isOnScreen(camera);
	}

	public var earlyPressWindow:Float = Flags.EARLY_HIT_WINDOW_RANGE;
	public var latePressWindow:Float = Flags.LATE_HIT_WINDOW_RANGE;

	public function updateSustain(strum:Strum) {
		var scrollSpeed = strum.getScrollSpeed(this);

		if (lastScrollSpeed != scrollSpeed) {
			lastScrollSpeed = scrollSpeed;
			if (nextSustain != null) {
				scale.y = (sustainLength * 0.45 * Math.abs(scrollSpeed)) / frameHeight;
				updateHitbox();
				scale.y += gapFix / frameHeight;
			}
		}

		updateSustainClip();
	}

	public function updateSustainClip() if (wasGoodHit && !noSustainClip) {
		var t = CoolUtil.bound((Conductor.songPosition - strumTime) / height * 0.45 * Math.abs(lastScrollSpeed), 0, 1);
		if (t != __lastSustainClipT || _frame == null) {
			__lastSustainClipT = t;
			@:bypassAccessor {
				if (clipRect == null) clipRect = FlxRect.get();
				clipRect.set(0, frameHeight * t, frameWidth, frameHeight * (1 - t));
			}
			@:privateAccess {
				if (frame != null && _frame != null)
					_frame = frame.clipTo(clipRect, _frame);
			}
		}
	}

	@:noCompletion
	override function set_clipRect(rect:FlxRect):FlxRect {
		@:bypassAccessor clipRect = rect;
		__lastSustainClipT = -1.0;

		@:privateAccess if (frame != null) {
			if (rect != null && _frame != null)
				_frame = frame.clipTo(rect, _frame);
			else if (_frame != null)
				_frame = frame.copyTo(_frame);
			dirty = true;
		}

		return rect;
	}

	public override function destroy() {
		super.destroy();

		clipRect = FlxDestroyUtil.put(clipRect);
	}
}
