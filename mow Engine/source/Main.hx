package;

import mikolka.vslice.components.crash.CrashServer;
import mikolka.vslice.components.DebugDisplay.FunkinDebugDisplay;
import mikolka.funkin.custom.mobile.MobileScaleMode;
import states.InitState;
import mikolka.vslice.components.crash.Logger;
#if HSCRIPT_ALLOWED
import crowplexus.iris.Iris;
import psychlua.HScript.HScriptInfos;
#end
import openfl.display.FPS;
import flixel.graphics.FlxGraphic;
import flixel.FlxGame;
import flixel.FlxState;
import flixel.FlxG;
import haxe.io.Path;
import openfl.Assets;
import openfl.Lib;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import openfl.display.StageScaleMode;
import lime.app.Application;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
#if (linux || mac)
import lime.graphics.Image;
#end

#if (cpp && windows)
@:cppInclude('windows.h')
@:cppInclude('dwmapi.h')
@:cppFileCode('#pragma comment(lib, "dwmapi.lib")')
#end

#if (linux && !debug)
@:cppInclude('./external/gamemode_client.h')
@:cppFileCode('#define GAMEMODE_AUTO')
#end

class Main extends Sprite
{
	public static final game = {
		width: 1280,
		height: 720,
		initialState: states.InitState,
		zoom: -1.0,
		framerate: 60,
		skipSplash: true,
		startFullscreen: false
	};
	public static var debugDisplay:FunkinDebugDisplay;
	public static final platform:String = #if mobile "Phones" #else "PCs" #end;

	#if (cpp && windows)
	private static function applyNativeDarkMode():Void
	{
		untyped __cpp__('
			HWND hWnd = GetActiveWindow();
			if (hWnd == NULL)
				hWnd = GetForegroundWindow();

			if (hWnd != NULL)
			{
				BOOL useDarkMode = TRUE;
				DwmSetWindowAttribute(hWnd, 20, &useDarkMode, sizeof(useDarkMode));
				DwmSetWindowAttribute(hWnd, 19, &useDarkMode, sizeof(useDarkMode));
				DWORD cornerPreference = 2; // DWMWCP_ROUND
				DwmSetWindowAttribute(hWnd, 33, &cornerPreference, sizeof(cornerPreference));
				COLORREF captionColor = RGB(0x1F, 0x1F, 0x1F);
				DwmSetWindowAttribute(hWnd, 35, &captionColor, sizeof(captionColor));
				COLORREF textColor = RGB(0xFF, 0xFF, 0xFF);
				DwmSetWindowAttribute(hWnd, 36, &textColor, sizeof(textColor));
				SetWindowPos(hWnd, NULL, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
			}
		');
	}
	#end

	public static function loadGameEarly()
	{
		CrashServer.init();
		#if (linux || mac || windows)
		try
		{
			var icon = lime.graphics.Image.fromFile("icon.png");
			if (icon != null)
				Lib.current.stage.window.setIcon(icon);
		}
		catch (e:Dynamic)
		{
			trace("Could not load window icon: " + e);
		}
		#end

		#if TITLE_SCREEN_EASTER_EGG
		if (Date.now().getMonth() == 0 && Date.now().getDate() == 14)
			Lib.current.stage.window.title = "Friday Night Funkin': Yasa's Engine";
		#end

		#if android
		StorageUtil.requestPermissions();
		Sys.setCwd(StorageUtil.getStorageDirectory());
		#end

		#if mobile
		extension.haptics.Haptic.initialize();
		#end
		#if sys
		Logger.startLogging();
		trace("CWD IS " + StorageUtil.getStorageDirectory());
		#end
		backend.CrashHandler.init();
		trace("Crash handler is up!");

		try
		{
			trace("Pushing global mods");
			#if LUA_ALLOWED
			Mods.pushGlobalMods();
			#end
			trace("Pushing top mod");
			Mods.loadTopMod();
		}
		catch (x:Exception)
			trace("Something went wrong with mod code: " + x.message);

		#if hxvlc
		trace("Starting hxvlc..");
		hxvlc.util.Handle.init(#if (hxvlc >= "1.8.0") ['--no-lua'] #end);
		#end
	}

	public static function main():Void
	{
		Lib.current.addChild(new Main());
	}

	public function new()
	{
		super();
		if (stage != null)
		{
			init();
		}
		else
		{
			addEventListener(Event.ADDED_TO_STAGE, init);
		}
	}

	private function init(?E:Event):Void
	{
		if (hasEventListener(Event.ADDED_TO_STAGE))
		{
			removeEventListener(Event.ADDED_TO_STAGE, init);
		}

		setupGame();
	}

	private function setupGame():Void
	{
		trace(backend.Native.buildSystemInfo());

		#if (openfl <= "9.2.0")
		var stageWidth:Int = Lib.current.stage.stageWidth;
		var stageHeight:Int = Lib.current.stage.stageHeight;
		if (game.zoom == -1.0)
		{
			var ratioX:Float = stageWidth / game.width;
			var ratioY:Float = stageHeight / game.height;
			game.zoom = Math.min(ratioX, ratioY);
			game.width = Math.ceil(stageWidth / game.zoom);
			game.height = Math.ceil(stageHeight / game.zoom);
		}
		#else
		if (game.zoom == -1.0)
			game.zoom = 1.0;
		#end

		FlxG.save.bind('MowEngine', CoolUtil.getSavePath(), (rawSave, error) ->
		{
			#if sys
			try
			{
				var badSave = File.write(StorageUtil.getStorageDirectory() + "/MowEngine.sol.bad");
				badSave.writeString(rawSave);
				badSave.close();
			}
			catch (x)
			{
				trace(x);
			}
			return {};
			#end
		});
		CrashServer.setupInstanceId();
		Highscore.load();

		#if HSCRIPT_ALLOWED
		Iris.warn = function(x, ?pos:haxe.PosInfos)
		{
			Iris.logLevel(WARN, x, pos);
			var newPos:HScriptInfos = cast pos;
			if (newPos.showLine == null)
				newPos.showLine = true;
			var msgInfo:String = (newPos.funcName != null ? '(${newPos.funcName}) - ' : '') + '${newPos.fileName}:';
			#if LUA_ALLOWED
			if (newPos.isLua == true)
			{
				msgInfo += 'HScript:';
				newPos.showLine = false;
			}
			#end
			if (newPos.showLine == true)
			{
				msgInfo += '${newPos.lineNumber}:';
			}
			msgInfo += ' $x';
			if (PlayState.instance != null)
				PlayState.instance.addTextToDebug('WARNING: $msgInfo', 0xFFFFFF00);
		}
		Iris.error = function(x, ?pos:haxe.PosInfos)
		{
			Iris.logLevel(ERROR, x, pos);
			var newPos:HScriptInfos = cast pos;
			if (newPos.showLine == null)
				newPos.showLine = true;
			var msgInfo:String = (newPos.funcName != null ? '(${newPos.funcName}) - ' : '') + '${newPos.fileName}:';
			#if LUA_ALLOWED
			if (newPos.isLua == true)
			{
				msgInfo += 'HScript:';
				newPos.showLine = false;
			}
			#end
			if (newPos.showLine == true)
			{
				msgInfo += '${newPos.lineNumber}:';
			}
			msgInfo += ' $x';
			if (PlayState.instance != null)
				PlayState.instance.addTextToDebug('ERROR: $msgInfo', 0xFFFF0000);
		}
		Iris.fatal = function(x, ?pos:haxe.PosInfos)
		{
			Iris.logLevel(FATAL, x, pos);
			var newPos:HScriptInfos = cast pos;
			if (newPos.showLine == null)
				newPos.showLine = true;
			var msgInfo:String = (newPos.funcName != null ? '(${newPos.funcName}) - ' : '') + '${newPos.fileName}:';
			#if LUA_ALLOWED
			if (newPos.isLua == true)
			{
				msgInfo += 'HScript:';
				newPos.showLine = false;
			}
			#end
			if (newPos.showLine == true)
			{
				msgInfo += '${newPos.lineNumber}:';
			}
			msgInfo += ' $x';
			if (PlayState.instance != null)
				PlayState.instance.addTextToDebug('FATAL: $msgInfo', 0xFFBB0000);
		}
		#end

		#if LUA_ALLOWED
		Lua.set_callbacks_function(cpp.Callable.fromStaticFunction(psychlua.CallbackHandler.call));
		#end

		Controls.instance = new Controls();
		ClientPrefs.loadDefaultKeys();
		#if ACHIEVEMENTS_ALLOWED Achievements.load(); #end

		var gameObject = new FlxGame(game.width, game.height, game.initialState, #if (flixel < "5.0.0") game.zoom, #end game.framerate, game.framerate,
			game.skipSplash, game.startFullscreen);
		
		@:privateAccess
		gameObject._customSoundTray = mikolka.vslice.components.FunkinSoundTray;
		addChild(gameObject);

		debugDisplay = new FunkinDebugDisplay(10, 10, 0xFFFFFF);
		debugDisplay.mouseEnabled = false;
		debugDisplay.mouseChildren = false;
		#if mobile
		FlxG.game.addChild(debugDisplay);
		#else
		addChild(debugDisplay);

		#if (cpp && windows)
		haxe.Timer.delay(applyNativeDarkMode, 100);
		#end
		#end

		Lib.current.stage.addEventListener(KeyboardEvent.KEY_DOWN, function(e:KeyboardEvent)
		{
			if (e.keyCode == Keyboard.F11)
			{
				FlxG.fullscreen = !FlxG.fullscreen;
			}
		});

		if (debugDisplay != null)
		{
			debugDisplay.visible = ClientPrefs.data.showFPSOpacity != 0;
			debugDisplay.backgroundOpacity = ClientPrefs.data.showFPSOpacity;
			debugDisplay.isAdvanced = ClientPrefs.data.fpsRework;
		}

		#if (debug)
		flixel.addons.studio.FlxStudio.create();
		#end

		FlxG.autoPause = false; 

		var savedVolume:Float = FlxG.sound.volume;

		Lib.current.stage.addEventListener(Event.DEACTIVATE, function(e:Event) {
			savedVolume = FlxG.sound.volume;
			FlxTween.cancelTweensOf(FlxG.sound);
			FlxTween.tween(FlxG.sound, {volume: 0.05}, 0.6, {ease: FlxEase.quadOut});
		});
		Lib.current.stage.addEventListener(Event.ACTIVATE, function(e:Event) {
			FlxTween.cancelTweensOf(FlxG.sound);
			FlxTween.tween(FlxG.sound, {volume: savedVolume}, 0.6, {ease: FlxEase.quadOut});
		});

		#if html5
		FlxG.mouse.visible = false;
		#end

		FlxG.fixedTimestep = false;
		FlxG.game.focusLostFramerate = #if mobile 30 #else 60 #end;
		#if web
		FlxG.keys.preventDefaultKeys.push(TAB);
		#else
		FlxG.keys.preventDefaultKeys = [TAB];
		#end

		#if DISCORD_ALLOWED
		DiscordClient.prepare();
		#end

		#if mobile
		#if android FlxG.android.preventDefaultKeys = [BACK]; #end
		lime.system.System.allowScreenTimeout = ClientPrefs.data.screensaver;
		#end

		// ปรับสเกลกล้องให้ตรงตามพิกัดหน้าต่างทันที ป้องกันอาการวูบขยายใหญ่
		FlxG.signals.gameResized.add(function(w, h)
		{
			if (FlxG.cameras != null)
			{
				for (cam in FlxG.cameras.list)
				{
					if (cam != null && cam.filters != null)
						resetSpriteCache(cam.flashSprite);
				}
			}

			if (FlxG.game != null)
			{
				resetSpriteCache(FlxG.game);
			}
		});
	}

	static function resetSpriteCache(sprite:Sprite):Void
	{
		@:privateAccess {
			sprite.__cacheBitmap = null;
			sprite.__cacheBitmapData = null;
		}
	}
}