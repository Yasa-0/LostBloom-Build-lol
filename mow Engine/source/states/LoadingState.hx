package states;

import lime.app.Future;
import sys.thread.FixedThreadPool;
import haxe.Json;
import lime.utils.Assets;
import openfl.display.BitmapData;
import openfl.utils.AssetType;
import openfl.utils.Assets as OpenFlAssets;
import flixel.graphics.FlxGraphic;
import flixel.system.FlxAssets;
import flixel.FlxState;
import flixel.FlxSprite;
import flixel.util.FlxColor;
import flixel.util.FlxAxes;
import flixel.math.FlxMath;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flash.media.Sound;
import backend.Song;
import backend.StageData;
import objects.Character;
import sys.thread.Thread;
import sys.thread.Mutex;
import objects.Note;
import objects.NoteSplash;

#if cpp
@:headerCode('
#include <iostream>
#include <thread>
')
#end
class LoadingState extends MusicBeatState
{
	public static var loaded:Int = 0;
	public static var loadMax:Int = 0;

	static var originalBitmapKeys:Map<String, String> = [];
	static var requestedBitmaps:Map<String, BitmapData> = [];
	static var mutex:Mutex;
	static var threadPool:FixedThreadPool = null;

	function new(target:FlxState, stopMusic:Bool)
	{
		this.target = target;
		this.stopMusic = stopMusic;

		super();
	}

	inline static public function loadAndSwitchState(target:FlxState, stopMusic = false, intrusive:Bool = true)
		MusicBeatState.switchState(getNextState(target, stopMusic, intrusive));

	var target:FlxState = null;
	var stopMusic:Bool = false;
	var dontUpdate:Bool = false;

	// ==========================================
	// ตัวแปรสำหรับหลอดโหลดด้านล่างจอ
	// ==========================================
	var whBar:FlxSprite;
	var startX:Float = 0;
	var intendedPercent:Float = 0;
	var curPercent:Float = 0;
	
	// บังคับดีเลย์ 1 วินาทีก่อนจะข้ามหน้า
	var stateChangeDelay:Float = 1.0; 

	override function create()
	{
		#if STRICT_LOADING_SCREEN
		if (backend.ClientPrefs.data.strictLoadingScreen)
		{
		#end
			CacheSystem.clearStoredMemory();
			CacheSystem.clearUnusedMemory();
			LoadingState.prepareToSong();
		#if STRICT_LOADING_SCREEN
		}
		#end

		persistentUpdate = true;

		// 1. ภาพพื้นหลัง loading_screen.png
		var lod = new FlxSprite(0, 0).loadGraphic(Paths.image('loading_screen/loading_screen'));
		lod.antialiasing = ClientPrefs.data.antialiasing;
		lod.setGraphicSize(FlxG.width, FlxG.height);
		lod.updateHitbox();
		lod.screenCenter();
		add(lod);

		// ==========================================
		// ปรับหลอดให้ลงต่ำไปอีก (ความหนา 10px ชิดติดขอบล่างสุด)
		// ==========================================
		var barHeight:Int = 10; // ลดขนาดความหนาลงเหลือ 10px เพื่อให้ลงต่ำชิดขอบล่างที่สุด
		var barY:Float = FlxG.height - barHeight;

		// 2. พื้นหลังหลอดสีดำ (กว้างเต็มจอ)
		var blackBar = new FlxSprite(0, barY).makeGraphic(FlxG.width, barHeight, FlxColor.BLACK);
		add(blackBar);

		// 3. หลอดสีขาวด้านใน (กว้างเต็มจอ เริ่มจากขอบซ้ายสุด)
		whBar = new FlxSprite(0, barY).makeGraphic(FlxG.width, barHeight, FlxColor.WHITE);
		startX = whBar.x; // อยู่ที่ 0 พอดี
		whBar.origin.set(0, 0); // เซ็ตจุดกำเนิดการขยายที่มุมซ้ายบน
		whBar.scale.x = 0;
		add(whBar);

		// 4. หน้าจอดำค่อยๆ จางออก (Fade In)
		var blacktran = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		add(blacktran);

		FlxTween.tween(blacktran, {alpha: 0}, 0.5, {
			ease: FlxEase.sineInOut
		});

		super.create();

		if (stateChangeDelay <= 0 && checkLoaded())
		{
			dontUpdate = true;
			onLoad();
		}
	}

	var transitioning:Bool = false;

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		if (dontUpdate)
			return;

		if (!transitioning)
		{
			if (!finishedLoading && checkLoaded())
			{
				if (stateChangeDelay <= 0)
				{
					transitioning = true;
					onLoad();
					return;
				}
				else
					stateChangeDelay = Math.max(0, stateChangeDelay - elapsed);
			}

			if (loadMax > 0)
				intendedPercent = loaded / loadMax;
			else
				intendedPercent = 0;

			intendedPercent = FlxMath.bound(intendedPercent, 0, 1);
		}

		// อัปเดตการวิ่งของหลอดสีขาวให้มีความนุ่มนวล (Lerp)
		if (curPercent != intendedPercent)
		{
			if (Math.abs(curPercent - intendedPercent) < 0.001)
				curPercent = intendedPercent;
			else
				curPercent = FlxMath.lerp(intendedPercent, curPercent, Math.exp(-elapsed * 15));

			whBar.scale.x = curPercent;
		}

		whBar.x = startX; // ล็อกจุดเริ่มไว้ที่ขอบซ้ายจอ
	}

	var finishedLoading:Bool = false;

	function onLoad()
	{
		_loaded();

		if (stopMusic && FlxG.sound.music != null)
			FlxG.sound.music.stop();

		FlxG.camera.visible = false;
		MusicBeatState.switchState(target);
		transitioning = true;
		finishedLoading = true;
	}

	static function _loaded()
	{
		loaded = 0;
		loadMax = 0;
		initialThreadCompleted = true;
		isIntrusive = false;

		FlxTransitionableState.skipNextTransIn = true;
		if (threadPool != null)
			threadPool.shutdown(); 
		threadPool = null;
		mutex = null;
	}

	public static function checkLoaded():Bool
	{
		for (key => bitmap in requestedBitmaps)
		{
			if (bitmap != null && CacheSystem.cacheBitmap(originalBitmapKeys.get(key), bitmap) != null)
			{
			} 
			else
				trace('failed to cache image $key');
		}
		requestedBitmaps.clear();
		originalBitmapKeys.clear();
		return (loaded >= loadMax && initialThreadCompleted);
	}

	public static function loadNextDirectory()
	{
		var directory:String = 'shared';
		var weekDir:String = StageData.forceNextDirectory;
		StageData.forceNextDirectory = null;

		if (weekDir != null && weekDir.length > 0 && weekDir != '')
			directory = weekDir;

		Paths.setCurrentLevel(directory);
		trace('Setting asset folder to ' + directory);
	}

	static var isIntrusive:Bool = false;

	static function getNextState(target:FlxState, stopMusic = false, intrusive:Bool = true):FlxState
	{
		#if !SHOW_LOADING_SCREEN
		intrusive = false;
		#end

		LoadingState.isIntrusive = intrusive;
		_startPool();
		loadNextDirectory();

		if (intrusive)
			return new LoadingState(target, stopMusic);

		if (stopMusic && FlxG.sound.music != null)
			FlxG.sound.music.stop();

		while (true)
		{
			if (checkLoaded())
			{
				_loaded();
				break;
			}
			else
				Sys.sleep(0.001);
		}
		return target;
	}

	static var imagesToPrepare:Array<String> = [];
	static var soundsToPrepare:Array<String> = [];
	static var musicToPrepare:Array<String> = [];
	static var songsToPrepare:Array<String> = [];

	public static function prepare(images:Array<String> = null, sounds:Array<String> = null, music:Array<String> = null)
	{
		if (images != null)
			imagesToPrepare = imagesToPrepare.concat(images);
		if (sounds != null)
			soundsToPrepare = soundsToPrepare.concat(sounds);
		if (music != null)
			musicToPrepare = musicToPrepare.concat(music);
	}

	static var initialThreadCompleted:Bool = true;
	static var dontPreloadDefaultVoices:Bool = false;

	static function _startPool()
	{
		threadPool = new FixedThreadPool(ClientPrefs.data.cacheOnCPU ? #if cpp getCPUThreadsCount() #else 4 #end : 1);
	}

	public static function prepareToSong()
	{
		if (PlayState.SONG == null)
		{
			imagesToPrepare.clear();
			soundsToPrepare.clear();
			musicToPrepare.clear();
			songsToPrepare.clear();
			loaded = 0;
			loadMax = 0;
			initialThreadCompleted = true;
			isIntrusive = false;
			return;
		}

		_startPool();
		imagesToPrepare.clear();
		soundsToPrepare.clear();
		musicToPrepare.clear();
		songsToPrepare.clear();

		initialThreadCompleted = false;
		var threadsCompleted:Int = 0;
		var threadsMax:Int = 0;
		function completedThread()
		{
			threadsCompleted++;
			if (threadsCompleted == threadsMax)
			{
				clearInvalids();
				startThreads();
				initialThreadCompleted = true;
			}
		}

		var song:SwagSong = PlayState.SONG;
		var folder:String = Paths.formatToSongPath(Song.loadedSongName);
		new Future<Bool>(() ->
		{
			var noteSkin:String = Note.defaultNoteSkin;
			if (PlayState.SONG.arrowSkin != null && PlayState.SONG.arrowSkin.length > 1)
				noteSkin = PlayState.SONG.arrowSkin;

			var customSkin:String = noteSkin + Note.getNoteSkinPostfix();
			if (Paths.fileExists('images/$customSkin.png', IMAGE))
				noteSkin = customSkin;
			imagesToPrepare.push(noteSkin);

			var noteSplash:String = NoteSplash.defaultNoteSplash;
			if (PlayState.SONG.splashSkin != null && PlayState.SONG.splashSkin.length > 0)
				noteSplash = PlayState.SONG.splashSkin;
			else
				noteSplash += NoteSplash.getSplashSkinPostfix();
			imagesToPrepare.push(noteSplash);

			try
			{
				var path:String = Paths.json('$folder/preload');
				var json:Dynamic = null;

				#if MODS_ALLOWED
				var moddyFile:String = Paths.modsJson('$folder/preload');
				if (NativeFileSystem.exists(moddyFile))
					json = Json.parse(NativeFileSystem.getContent(moddyFile));
				else
					json = Json.parse(NativeFileSystem.getContent(path));
				#end

				if (json != null)
				{
					var imgs:Array<String> = [];
					var snds:Array<String> = [];
					var mscs:Array<String> = [];
					for (asset in Reflect.fields(json))
					{
						var filters:Int = Reflect.field(json, asset);
						var asset:String = asset.trim();

						if (filters < 0 || StageData.validateVisibility(filters))
						{
							if (asset.startsWith('images/'))
								imgs.push(asset.substr('images/'.length));
							else if (asset.startsWith('sounds/'))
								snds.push(asset.substr('sounds/'.length));
							else if (asset.startsWith('music/'))
								mscs.push(asset.substr('music/'.length));
						}
					}
					prepare(imgs, snds, mscs);
				}
			}
			catch (e:Dynamic)
			{
			}
			return true;
		}, isIntrusive).then((_) -> new Future<Bool>(() ->
			{
				if (song.stage == null || song.stage.length < 1)
					song.stage = StageData.vanillaSongStage(folder);

				var stageData:StageFile = StageData.getStageFile(song.stage);
				if (stageData != null)
				{
					var imgs:Array<String> = [];
					var snds:Array<String> = [];
					var mscs:Array<String> = [];
					if (stageData.preload != null)
					{
						for (asset in Reflect.fields(stageData.preload))
						{
							var filters:Int = Reflect.field(stageData.preload, asset);
							var asset:String = asset.trim();

							if (filters < 0 || StageData.validateVisibility(filters))
							{
								if (asset.startsWith('images/'))
									imgs.push(asset.substr('images/'.length));
								else if (asset.startsWith('sounds/'))
									snds.push(asset.substr('sounds/'.length));
								else if (asset.startsWith('music/'))
									mscs.push(asset.substr('music/'.length));
							}
						}
					}

					if (stageData.objects != null)
					{
						for (sprite in stageData.objects)
						{
							if (sprite.type == 'sprite' || sprite.type == 'animatedSprite')
								if ((sprite.filters < 0 || StageData.validateVisibility(sprite.filters)) && !imgs.contains(sprite.image))
									imgs.push(sprite.image);
						}
					}
					prepare(imgs, snds, mscs);
				}

				if (PlayState.altInstrumentals != null)
				{
					songsToPrepare.push('${Paths.formatToSongPath(PlayState.altInstrumentals)}/Inst');
				}
				else
					songsToPrepare.push('$folder/Inst');

				var player1:String = song.player1;
				var player2:String = song.player2;
				var gfVersion:String = song.gfVersion;
				var prefixVocals:String = song.needsVoices ? '$folder/Voices' : null;
				if (gfVersion == null)
					gfVersion = 'gf';

				dontPreloadDefaultVoices = false;
				preloadCharacter(player1, prefixVocals);
				if (!dontPreloadDefaultVoices && prefixVocals != null)
				{
					if (Paths.fileExists('$prefixVocals-Player.${Paths.SOUND_EXT}', SOUND, false, 'songs')
						&& Paths.fileExists('$prefixVocals-Opponent.${Paths.SOUND_EXT}', SOUND, false, 'songs'))
					{
						songsToPrepare.push('$prefixVocals-Player');
						songsToPrepare.push('$prefixVocals-Opponent');
					}
					else if (Paths.fileExists('$prefixVocals.${Paths.SOUND_EXT}', SOUND, false, 'songs'))
						songsToPrepare.push(prefixVocals);
				}

				if (player2 != player1)
				{
					threadsMax++;
					threadPool.run(() ->
					{
						try
						{
							preloadCharacter(player2, prefixVocals);
						}
						catch (e:Dynamic)
						{
						}
						completedThread();
					});
				}
				if (!stageData.hide_girlfriend && gfVersion != player2 && gfVersion != player1)
				{
					threadsMax++;
					threadPool.run(() ->
					{
						try
						{
							preloadCharacter(gfVersion);
						}
						catch (e:Dynamic)
						{
						}
						completedThread();
					});
				}

				if (threadsCompleted == threadsMax)
				{
					clearInvalids();
					startThreads();
					initialThreadCompleted = true;
				}
				return true;
			}, isIntrusive)).onError((err:Dynamic) ->
			{
				trace('ERROR! while preparing song: $err');
			});
	}

	public static function clearInvalids()
	{
		clearInvalidFrom(imagesToPrepare, 'images', '.png', IMAGE);
		clearInvalidFrom(soundsToPrepare, 'sounds', '.${Paths.SOUND_EXT}', SOUND);
		clearInvalidFrom(musicToPrepare, 'music', '.${Paths.SOUND_EXT}', SOUND);
		clearInvalidFrom(songsToPrepare, 'songs', '.${Paths.SOUND_EXT}', SOUND, 'songs');

		for (arr in [imagesToPrepare, soundsToPrepare, musicToPrepare, songsToPrepare])
			while (arr.contains(null))
				arr.remove(null);
	}

	static function clearInvalidFrom(arr:Array<String>, prefix:String, ext:String, type:AssetType, ?parentFolder:String = null)
	{
		for (folder in arr.copy())
		{
			var nam:String = folder.trim();
			if (nam.endsWith('/'))
			{
				for (subfolder in Mods.directoriesWithFile(Paths.getSharedPath(), '$prefix/$nam'))
				{
					for (file in NativeFileSystem.readDirectory(subfolder))
					{
						if (file.endsWith(ext))
						{
							var toAdd:String = nam + haxe.io.Path.withoutExtension(file);
							if (!arr.contains(toAdd))
								arr.push(toAdd);
						}
					}
				}
			}
		}

		var i:Int = 0;
		while (i < arr.length)
		{
			var member:String = arr[i];
			var myKey = '$prefix/$member$ext';
			if (parentFolder == 'songs')
				myKey = '$member$ext';

			var doTrace:Bool = false;
			if (member.endsWith('/') || (!Paths.fileExists(myKey, type, false, parentFolder) && (doTrace = true)))
			{
				arr.remove(member);
				if (doTrace)
					trace('Removed invalid $prefix: $member');
			}
			else
				i++;
		}
	}

	public static function startThreads()
	{
		if(mutex != null){
			trace("Mutex already made! Cancelling this request!");
			return;
		}
		mutex = new Mutex();
		trace("Made mutex");
		loadMax = imagesToPrepare.length + soundsToPrepare.length + musicToPrepare.length + songsToPrepare.length;
		loaded = 0;

		_threadFunc();
	}

	static function _threadFunc()
	{
		_startPool();
		for (sound in soundsToPrepare)
			initThread(() -> preloadSound('sounds/$sound'), 'sound $sound');
		for (music in musicToPrepare)
			initThread(() -> preloadSound('music/$music'), 'music $music');
		for (song in songsToPrepare)
			initThread(() -> preloadSound(song, 'songs', true, false), 'song $song');

		for (image in imagesToPrepare)
			initThread(() -> preloadGraphic(image), 'image $image');
	}

	static function initThread(func:Void->Dynamic, traceData:String)
	{
		#if debug
		var threadSchedule = Sys.time();
		#end
		threadPool.run(() ->
		{
			#if debug
			var threadStart = Sys.time();
			trace('$traceData took ${threadStart - threadSchedule}s to start preloading');
			#end

			try
			{
				if (func() != null)
				{
					#if debug
					var diff = Sys.time() - threadStart;
					trace('finished preloading $traceData in ${diff}s');
					#end
				}
				else
					trace('ERROR! fail on preloading $traceData ');
			}
			catch (e:Dynamic)
			{
				trace('ERROR! fail on preloading $traceData: $e');
			}
			mutex.acquire();
			loaded++;
			trace('$loaded/$loadMax assets loaded');
			mutex.release();
		});
	}

	inline private static function preloadCharacter(char:String, ?prefixVocals:String)
	{
		try
		{
			var path:String = Paths.getPath('characters/$char.json', TEXT);
			var character:Dynamic = Json.parse(NativeFileSystem.getContent(path));

			var isAnimateAtlas:Bool = false;
			var img:String = character.image;
			img = img.trim();
			#if flxanimate
			var animToFind:String = Paths.getPath('images/$img/Animation.json', TEXT);
			if (#if MODS_ALLOWED NativeFileSystem.exists(animToFind) || #end Assets.exists(animToFind))
				isAnimateAtlas = true;
			#end

			if (!isAnimateAtlas)
			{
				var split:Array<String> = img.split(',');
				for (file in split)
				{
					imagesToPrepare.push(file.trim());
				}
			}
			#if flxanimate
			else
			{
				for (i in 0...10)
				{
					var st:String = '$i';
					if (i == 0)
						st = '';

					if (Paths.fileExists('images/$img/spritemap$st.png', IMAGE))
					{
						imagesToPrepare.push('$img/spritemap$st');
						break;
					}
				}
			}
			#end

			if (prefixVocals != null && character.vocals_file != null && character.vocals_file.length > 0)
			{
				songsToPrepare.push(prefixVocals + "-" + character.vocals_file);
				if (char == PlayState.SONG.player1)
					dontPreloadDefaultVoices = true;
			}
		}
		catch (e:haxe.Exception)
		{
			trace(e.details());
		}
	}

	static function preloadSound(key:String, ?path:String, ?modsAllowed:Bool = true, ?beepOnNull:Bool = true):Null<Sound>
	{
		var file:String = Paths.getPath(Language.getFileTranslation(key) + '.${Paths.SOUND_EXT}', SOUND, path, modsAllowed);

		if (!CacheSystem.currentTrackedSounds.exists(file))
		{
			var sound:Sound = NativeFileSystem.getSound(file);
			if (sound != null)
			{
				mutex.acquire();
				CacheSystem.currentTrackedSounds.set(file, sound);
				mutex.release();
			}
			else if (beepOnNull)
			{
				trace('SOUND NOT FOUND: $key, PATH: $path');
				FlxG.log.error('SOUND NOT FOUND: $key, PATH: $path');
				return FlxAssets.getSound('flixel/sounds/beep');
			}
		}
		mutex.acquire();
		CacheSystem.localTrackedAssets.push(file);
		mutex.release();

		return CacheSystem.currentTrackedSounds.get(file);
	}

	static function preloadGraphic(key:String):Null<BitmapData>
	{
		try
		{
			var requestKey:String = 'images/$key';
			#if TRANSLATIONS_ALLOWED requestKey = Language.getFileTranslation(requestKey); #end
			var baseReqKey = requestKey;
			if (requestKey.lastIndexOf('.') < 0)
				requestKey += '.png';

			if (!CacheSystem.currentTrackedAssets.exists(requestKey))
			{
				var bitmap:BitmapData = null;
				var file:String = Paths.getPath(requestKey, IMAGE);

				#if ATSC_SUPPORT
				if (Paths.fileExists(baseReqKey + '.astc', IMAGE))
					return null;
				#end

				if (bitmap == null)
					bitmap = NativeFileSystem.getBitmap(file);

				if (bitmap != null)
				{
					mutex.acquire();
					requestedBitmaps.set(file, bitmap);
					originalBitmapKeys.set(file, requestKey);
					mutex.release();
					return bitmap;
				}
				else
					trace('no such image $key exists');
			}

			return CacheSystem.currentTrackedAssets.get(requestKey).bitmap;
		}
		catch (e:haxe.Exception)
		{
			trace('ERROR! fail on preloading image $key ${e.details()}');
		}

		return null;
	}

	#if cpp
	@:functionCode('
		return std::thread::hardware_concurrency();
    	')
	@:noCompletion
	public static function getCPUThreadsCount():Int
	{
		trace("Running base implementation. Did the cpp code break?");
		return 2;
	}
	#end
}