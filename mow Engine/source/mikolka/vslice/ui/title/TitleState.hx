package mikolka.vslice.ui.title;

import mikolka.vslice.ui.title.IntroSubstate;
import mikolka.funkin.custom.mobile.MobileScaleMode;
import mikolka.compatibility.VsliceOptions;
import flixel.group.FlxGroup;
import haxe.Json;
import openfl.Assets;
import mikolka.vslice.components.crash.Logger;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxTimer;
import flixel.math.FlxPoint;
import flixel.math.FlxMath;
import flixel.util.FlxColor;
import flixel.text.FlxText;

/**
 * โครงสร้างข้อมูลสำหรับ Title JSON
 */
typedef TitleData =
{
	var titlex:Float;
	var titley:Float;
	var startx:Float;
	var starty:Float;
	var gfx:Float;
	var gfy:Float;
	var backgroundSprite:String;
	var bpm:Float;
}

class TitleState extends MusicBeatState
{
	public static var initialized:Bool = false;
	public static var closedState:Bool = false;

	var logoBl:FlxSprite;
	var titleText:FlxSprite;
	var logoPosition:FlxPoint = FlxPoint.get(-100, -300);
	var enterPosition:FlxPoint = FlxPoint.get(100, 576);
	var musicBPM:Float = 102;

	var lerpScore:Float = 0;
	var sickBeats:Int = 0; 
	var skippedIntro:Bool = false;
	var transitioning:Bool = false;

	override public function create():Void
	{
		#if sys
		Logger.enforceLogSettings = true;
		#end

		CacheSystem.clearStoredMemory();
		CacheSystem.clearUnusedMemory();

		closedState = false;
		super.create();
		
		startIntro();
	}

	function startIntro()
	{
		persistentUpdate = true;
		loadTitleJson(); 
		Conductor.bpm = musicBPM;
		if (!initialized && FlxG.sound.music == null)
			FlxG.sound.playMusic(Paths.music('freakyMenu'), 0);

		// สร้าง Object ไว้เพื่อป้องกัน Error ในจุดอื่น แต่ตั้งค่าให้ไม่แสดงผล
		logoBl = new FlxSprite(-900, logoPosition.y); 
		logoBl.frames = Paths.getSparrowAtlas('logoBumpin');
		logoBl.antialiasing = VsliceOptions.ANTIALIASING;
		logoBl.visible = false; 
		add(logoBl);

		titleText = new FlxSprite(enterPosition.x, enterPosition.y);
		titleText.frames = Paths.getSparrowAtlas('titleEnter');
		titleText.animation.addByPrefix('idle', "ENTER IDLE", 24);
		titleText.visible = false;
		add(titleText);

		if (initialized) skipIntro();
		else {
			openSubState(new IntroSubstate());
			initialized = true;
		}
	}

	override function update(elapsed:Float)
	{
		if (FlxG.sound.music != null)
			Conductor.songPosition = FlxG.sound.music.time;

		handleInput();
		super.update(elapsed);
	}

	function handleInput()
	{
		var pressedEnter:Bool = FlxG.keys.justPressed.ENTER || controls.ACCEPT;
		if (initialized && pressedEnter && !skippedIntro) 
		{
			skipIntro(); 
		}
	}

	function loadTitleJson() 
	{
		var path:String = 'images/gfDanceTitle.json';
		if (Paths.fileExists(path, TEXT)) 
		{
			var raw:String = Paths.getTextFromFile(path);
			try {
				var json:TitleData = Json.parse(raw);
				logoPosition.set(json.titlex, json.titley);
				enterPosition.set(json.startx, json.starty);
				musicBPM = json.bpm;
			} catch (e:haxe.Exception) {
				trace("Critical Error: Title JSON parsing failed.");
			}
		}
	}

	override function beatHit() 
	{
		super.beatHit();

		if (!closedState) 
		{
			sickBeats++;
			switch (sickBeats) {
				case 1: if (FlxG.sound.music != null) FlxG.sound.music.fadeIn(4, 0, 0.7);
				case 17: if (!skippedIntro) skipIntro(); 
			}
		}
	}

	function skipIntro():Void 
	{
		if (!skippedIntro) 
		{
			if (subState != null) closeSubState(); 
			
			skippedIntro = true;
			transitioning = true;
			closedState = true;

			// ใช้คำสั่งเดิมจากไฟล์ที่คุณส่งมา (อิงจาก )
			MusicBeatState.switchState(new MainMenuState());
		}
	}

	override function destroy()
	{
		super.destroy();
		logoPosition = null;
		enterPosition = null;
	}
}