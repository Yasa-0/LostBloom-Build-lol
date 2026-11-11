package options;

import flixel.FlxG;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import flixel.FlxSprite;
import flixel.sound.FlxSound;
import backend.ClientPrefs;

#if sys
import sys.FileSystem;
#end
import haxe.io.Path;
import lime.ui.FileDialog;
import lime.ui.FileDialogType;
import openfl.media.Sound;

using StringTools;

class MenuMusicSubState extends MusicBeatSubstate
{
	var songOptions:Array<String> = ['freakyMenu', 'freakyMenu-alt']; 
	var grpTexts:FlxTypedGroup<FlxText>;
	var curSelected:Int = 0;
	
	var fileDialog:FileDialog;
	var highlightBox:FlxSprite;
	var pageText:FlxText;
	var MAX_PER_PAGE:Int = 10; // ลดจำนวนต่อหน้าลงนิดหน่อยเพื่อเผื่อที่ให้ข้อความเตือน
	var previewSound:FlxSound;

	// --- ฟังก์ชันช่วยเหลือสำหรับอ่านไฟล์จากนอกเกมโดยเฉพาะ (ใส่ดัก Error กันหลุดแล้ว) ---
	public static function getCustomMusic(path:String):Dynamic {
		if (path == null) return null;
		#if sys
		if (path.contains("/") || path.contains("\\")) {
			if (FileSystem.exists(path)) {
				try {
					return Sound.fromFile(path);
				} catch(e:Dynamic) {
					trace("Error loading sound: " + e);
					return null; // ถ้าโหลด mp3 แล้วพัง จะคืนค่า null แทนการทำให้เกมแครช
				}
			}
			return null;
		}
		#end
		try { return Paths.music(path); } catch(e:Dynamic) { return null; }
	}

	public static function getCustomInRoom(path:String):Dynamic {
		if (path == null) return null;
		#if sys
		if (path.contains("/") || path.contains("\\")) {
			var ext = Path.extension(path);
			var noExt = path.substring(0, path.length - ext.length - 1);
			var inRoomPath = noExt + "InRoom." + ext;
			if (FileSystem.exists(inRoomPath)) {
				try {
					return Sound.fromFile(inRoomPath);
				} catch(e:Dynamic) {
					return null;
				}
			}
			return null;
		}
		#end
		try { return Paths.music(path + 'InRoom'); } catch(e:Dynamic) { return null; }
	}
	// --------------------------------------------------

	public function new()
	{
		super();
		
		if (OptionsState.inRoomMusic != null && OptionsState.inRoomMusic.playing) {
			OptionsState.inRoomMusic.volume = 0;
		}
		if (FlxG.sound.music != null) {
			FlxG.sound.music.volume = 0;
		}

		#if sys
		var customMusicPath = "mods/music/";
		if (FileSystem.exists(customMusicPath)) {
			for (file in FileSystem.readDirectory(customMusicPath)) {
				if (file.endsWith(".ogg") || file.endsWith(".mp3") || file.endsWith(".wav")) {
					var name = file.substring(0, file.lastIndexOf('.'));
					if (!songOptions.contains(name)) songOptions.push(name);
				}
			}
		}
		#end

		var currentMenu = ClientPrefs.data.menuMusic;
		if (currentMenu != null && !songOptions.contains(currentMenu) && (currentMenu.contains("/") || currentMenu.contains("\\"))) {
			#if sys
			if (FileSystem.exists(currentMenu)) {
				songOptions.push(currentMenu);
			} else {
				ClientPrefs.data.menuMusic = 'freakyMenu';
				currentMenu = 'freakyMenu';
			}
			#else
			songOptions.push(currentMenu);
			#end
		}

		songOptions.push('Upload Custom Song...'); 

		var bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		add(bg);

		var header1 = new FlxText(20, 10, 0, "Choose Menu Music:", 24);
		header1.setFormat(Paths.font("PressStart2P.ttf"), 20, 0xFFCCCCCC, LEFT); 
		add(header1);

		var header2 = new FlxText(20, 40, 0, "Use UP/DOWN to preview, ENTER to equip.", 24);
		header2.setFormat(Paths.font("PressStart2P.ttf"), 16, 0xFFCCCCCC, LEFT);
		add(header2);

		var warnText = new FlxText(20, 70, 0, "* WARNING: Highly recommend using .OGG or .WAV\n  .MP3 files may cause the game to crash!", 16);
		warnText.setFormat(Paths.font("PressStart2P.ttf"), 12, FlxColor.RED, LEFT);
		add(warnText);

		highlightBox = new FlxSprite(20, 0).makeGraphic(FlxG.width - 40, 35, 0xFF888888);
		add(highlightBox);

		grpTexts = new FlxTypedGroup<FlxText>();
		add(grpTexts);

		pageText = new FlxText(FlxG.width - 250, FlxG.height - 40, 230, "", 24);
		pageText.setFormat(Paths.font("PressStart2P.ttf"), 16, 0xFFCCCCCC, RIGHT);
		add(pageText);

		refreshMenu();

		curSelected = songOptions.indexOf(ClientPrefs.data.menuMusic);
		if(curSelected == -1) curSelected = 0;

		changeSelection(0);
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (controls.UI_UP_P) changeSelection(-1);
		if (controls.UI_DOWN_P) changeSelection(1);

		if (FlxG.mouse.wheel != 0) {
			changeSelection(-FlxG.mouse.wheel);
		}

		if (controls.BACK || FlxG.mouse.justPressedRight)
		{
			if (previewSound != null) {
				previewSound.stop();
				previewSound.destroy();
			}
			
			var soundToPlay = getCustomMusic(ClientPrefs.data.menuMusic);
			if (soundToPlay != null) FlxG.sound.playMusic(soundToPlay, 1);

			if (OptionsState.inRoomMusic != null) {
				var inRoomSound = getCustomInRoom(ClientPrefs.data.menuMusic);
				if (inRoomSound != null) {
					OptionsState.inRoomMusic.loadEmbedded(inRoomSound, true);
					OptionsState.inRoomMusic.play();
					OptionsState.inRoomMusic.volume = 0; 
				} else {
					OptionsState.inRoomMusic.stop();
					OptionsState.inRoomMusic.active = false;
				}
			}

			FlxG.sound.play(Paths.sound('back'));
			close();
		}

		if (controls.ACCEPT || FlxG.mouse.justPressed)
		{
			if (songOptions[curSelected] == 'Upload Custom Song...')
			{
				openFileUpload();
			}
			else
			{
				ClientPrefs.data.menuMusic = songOptions[curSelected];
				ClientPrefs.saveSettings();
				FlxG.sound.play(Paths.sound('next'));
				changeSelection(0); 
			}
		}
	}

	function changeSelection(change:Int)
	{
		curSelected = FlxMath.wrap(curSelected + change, 0, songOptions.length - 1);

		if (change != 0) FlxG.sound.play(Paths.sound('lick'));

		var totalPages = Math.ceil(songOptions.length / MAX_PER_PAGE);
		var curPage = Math.floor(curSelected / MAX_PER_PAGE);

		pageText.text = (totalPages > 1) ? "Page " + (curPage + 1) + " / " + totalPages : "";

		// ขยับจุดเริ่มต้นรายชื่อลงมาเพื่อไม่ให้ทับกับข้อความเตือนสีแดง
		var startY = 110;
		for (num => item in grpTexts.members)
		{
			if (num >= curPage * MAX_PER_PAGE && num < (curPage + 1) * MAX_PER_PAGE)
			{
				item.visible = true;
				item.y = startY + ((num % MAX_PER_PAGE) * 35); 
				
				if (songOptions[num] == ClientPrefs.data.menuMusic) {
					item.color = FlxColor.YELLOW; 
				} else if (num == curSelected) {
					item.color = FlxColor.WHITE; 
				} else {
					item.color = 0xFFCCCCCC; 
				}

				if (num == curSelected) highlightBox.y = item.y - 4;
			}
			else
			{
				item.visible = false;
			}
		}

		if (songOptions[curSelected] != 'Upload Custom Song...')
		{
			if (previewSound != null) {
				previewSound.stop();
				previewSound.destroy();
			}

			var soundToPlay = getCustomMusic(songOptions[curSelected]);
			if (soundToPlay != null) {
				previewSound = new FlxSound().loadEmbedded(soundToPlay, true);
				previewSound.volume = 1;
				previewSound.play();
				FlxG.sound.list.add(previewSound);
			}
		} else {
			if (previewSound != null) previewSound.stop();
		}
	}

	function openFileUpload()
	{
		#if sys
		fileDialog = new FileDialog();
		fileDialog.onSelect.add(onFileSelected);
		fileDialog.onCancel.add(onFileCancel);
		// แจ้งเตือนย้ำในหน้าต่าง Windows File Explorer
		fileDialog.browse(FileDialogType.OPEN, "ogg,wav,mp3", null, "Select Custom Music (OGG/WAV recommended)");
		#end
	}

	#if sys
	function onFileSelected(fullPath:String)
	{
		var songPath = fullPath; 

		songOptions.remove('Upload Custom Song...');
		if (!songOptions.contains(songPath)) {
			songOptions.push(songPath);
		}
		songOptions.push('Upload Custom Song...');
		
		ClientPrefs.data.menuMusic = songPath;
		ClientPrefs.saveSettings();

		refreshMenu();
		
		curSelected = songOptions.indexOf(songPath);
		changeSelection(0);
		
		FlxG.sound.play(Paths.sound('next'));
	}

	function onFileCancel() { 
		fileDialog = null; 
	}
	#end

	function refreshMenu()
	{
		grpTexts.clear();
		for (i in 0...songOptions.length)
		{
			var displayName = songOptions[i];
			
			#if sys
			if (displayName != 'Upload Custom Song...' && (displayName.contains("/") || displayName.contains("\\"))) {
				displayName = Path.withoutDirectory(displayName);
			}
			#end

			var text = new FlxText(60, 0, 0, displayName, 16);
			text.setFormat(Paths.font("PressStart2P.ttf"), 16, 0xFFCCCCCC, LEFT);
			text.ID = i;
			grpTexts.add(text);
		}
	}
}