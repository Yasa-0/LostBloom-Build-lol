package options;

import mikolka.funkin.custom.mobile.MobileScaleMode;
import mikolka.vslice.components.crash.UserErrorSubstate;
import backend.StageData;
import backend.ClientPrefs;
import flixel.FlxObject;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.math.FlxMath;
import flixel.sound.FlxSound;

class OptionsState extends MusicBeatState
{
	var options:Array<String> = [
		'Controls',
		'Graphics',
		'Visuals',
		'Gameplay',
		'V-Slice Options',
		#if (TOUCH_CONTROLS_ALLOWED || mobile)'Mobile Options', #end
		'Menu Music' 
	];
	
	private var grpOptions:FlxTypedGroup<FlxText>;
	private var highlightBox:FlxSprite;
	private var pageText:FlxText;
	
	private static var curSelected:Int = 0;
	public static var menuBG:FlxSprite;
	public static var onPlayState:Bool = false;
	var exiting:Bool = false;

	private var mainCam:FlxCamera;
	public static var funnyCam:FlxCamera;

	var oldMusicVolume:Float = -1;
	var MAX_PER_PAGE:Int = 10;

	public static var inRoomMusic:FlxSound;

	function openSelectedSubstate(label:String) {
		if (label != "Adjust Delay and Combo")
			funnyCam.visible = persistentUpdate = false;

		switch(label)
		{
			case 'Controls':
				if (controls.mobileC)
				{
					funnyCam.visible = persistentUpdate = true;
					UserErrorSubstate.makeMessage("Unsupported controls", 
					"You don't need to go there on mobile!\n\nIf you wish to go there anyway\nSet 'Mobile Controls Opacity' to 0%");
				}
				else
					openSubState(new options.ControlsSubState());
			case 'Graphics':
				openSubState(new options.GraphicsSettingsSubState());
			case 'Visuals':
				openSubState(new options.VisualsSettingsSubState());
			case 'Gameplay':
				openSubState(new options.GameplaySettingsSubState());
			case 'V-Slice Options':
				openSubState(new VSliceSubState());
			#if (TOUCH_CONTROLS_ALLOWED || mobile)
			case 'Mobile Options':
				openSubState(new mobile.options.MobileOptionsSubState());
			#end
			case 'Menu Music':
				openSubState(new options.MenuMusicSubState());
		}
	}

	override function create()
	{
		// ดึงไฟล์ InRoom ด้วยฟังก์ชันจาก MenuMusicSubState ถ้าไม่มีจะคืนค่า null ให้เกมเงียบไป
		if (inRoomMusic == null || !inRoomMusic.active)
		{
			try {
				var soundFile = MenuMusicSubState.getCustomInRoom(ClientPrefs.data.menuMusic);
				
				if (soundFile != null) {
					inRoomMusic = new FlxSound();
					inRoomMusic.loadEmbedded(soundFile, true);
					inRoomMusic.volume = 0;
					inRoomMusic.play();
					FlxG.sound.list.add(inRoomMusic);
				} else {
					inRoomMusic = null; 
				}
			} catch(e:Dynamic) {
				inRoomMusic = null;
			}
		}

		if (FlxG.sound.music != null && FlxG.sound.music.playing)
		{
			oldMusicVolume = FlxG.sound.music.volume;
			FlxG.sound.music.volume = 0; 

			if (inRoomMusic != null && inRoomMusic.active)
			{
				inRoomMusic.time = FlxG.sound.music.time;
				inRoomMusic.volume = 0.7; 
				if (!inRoomMusic.playing) inRoomMusic.play();
			}
		}

		FlxG.mouse.visible = true;

		mainCam = initPsychCamera();
		funnyCam = new FlxCamera();
		funnyCam.bgColor.alpha = 0;
		FlxG.cameras.add(funnyCam, false);

		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Options Menu", null);
		#end

		var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		bg.cameras = [mainCam];
		add(bg);

		var header1 = new FlxText(20, 10, 0, "Choose an Option Category:", 16);
		header1.setFormat(Paths.font("PressStart2P.ttf"), 16, 0xFFCCCCCC, LEFT); 
		header1.cameras = [mainCam];
		add(header1);

		var header2 = new FlxText(20, 40, 0, "Use the up and down arrow keys to move the highlight to your choice.", 16);
		header2.setFormat(Paths.font("PressStart2P.ttf"), 16, 0xFFCCCCCC, LEFT);
		header2.cameras = [mainCam];
		add(header2);

		highlightBox = new FlxSprite(20, 0).makeGraphic(FlxG.width - 40, 35, 0xFF888888);
		highlightBox.cameras = [funnyCam];
		add(highlightBox);

		grpOptions = new FlxTypedGroup<FlxText>();
		add(grpOptions);

		for (num => option in options)
		{
			var optionText:FlxText = new FlxText(60, 0, 0, Language.getPhrase('options_$option', option), 16);
			optionText.setFormat(Paths.font("PressStart2P.ttf"), 16, 0xFFCCCCCC, LEFT);
			optionText.ID = num;
			optionText.cameras = [funnyCam];
			grpOptions.add(optionText);
		}

		pageText = new FlxText(FlxG.width - 220, FlxG.height - 40, 200, "", 16);
		pageText.setFormat(Paths.font("PressStart2P.ttf"), 16, 0xFFCCCCCC, RIGHT);
		pageText.cameras = [mainCam];
		add(pageText);

		changeSelection(0);
		ClientPrefs.saveSettings();

		#if TOUCH_CONTROLS_ALLOWED
		addTouchPad('UP_DOWN', 'A_B');
		var button = new TouchZone(90,270,FlxG.width,100,FlxColor.PURPLE);
		var scroll = new ScrollableObject(-0.01,100,0,FlxG.width-200,FlxG.height,button);
		scroll.onPartialScroll.add(delta -> changeSelection(Std.int(delta)));
        scroll.onFullScrollSnap.add(() ->changeSelection(0));
		scroll.onTap.add(() ->{
			FlxG.sound.play(Paths.sound('next'));
			openSelectedSubstate(options[curSelected]);
		});
		add(scroll);
		add(button);
		#end
		
		super.create();
	}

	override function closeSubState()
	{
		super.closeSubState();
		ClientPrefs.saveSettings();
		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Options Menu", null);
		#end
		controls.isInSubstate = false;
		persistentUpdate = funnyCam.visible = true;
		
		#if TOUCH_CONTROLS_ALLOWED
		removeTouchPad();
		addTouchPad('UP_DOWN', 'A_B');
		#end
	}

	override function update(elapsed:Float) {
		super.update(elapsed);
		if(exiting) return;

		if (FlxG.sound.music != null && inRoomMusic != null && inRoomMusic.active)
		{
			if (Math.abs(inRoomMusic.time - FlxG.sound.music.time) > 20)
				inRoomMusic.time = FlxG.sound.music.time;
		}

		if (FlxG.mouse.wheel != 0) {
			FlxG.sound.play(Paths.sound('lick'));
			changeSelection(-FlxG.mouse.wheel);
		}
		
		if (FlxG.mouse.justMoved) {
			var mousePos = FlxG.mouse.getWorldPosition(funnyCam);
			for (i in 0...grpOptions.members.length) {
				var item = grpOptions.members[i];
				if (item.visible && mousePos.y >= item.y && mousePos.y <= item.y + item.height && mousePos.x >= 20 && mousePos.x <= FlxG.width - 20) {
					if (curSelected != i) {
						curSelected = i;
						FlxG.sound.play(Paths.sound('lick'));
						changeSelection(0);
					}
					break;
				}
			}
		}

		if (controls.UI_UP_P){
			FlxG.sound.play(Paths.sound('lick'));
			changeSelection(-1);
		}
		if (controls.UI_DOWN_P){
			FlxG.sound.play(Paths.sound('lick'));
			changeSelection(1);
		}

		if (controls.BACK || FlxG.mouse.justPressedRight)
		{
			FlxG.sound.play(Paths.sound('back'));
			exiting = true;
			
			if (FlxG.sound.music != null)
				FlxG.sound.music.volume = (oldMusicVolume != -1) ? oldMusicVolume : 1;

			if (inRoomMusic != null && inRoomMusic.active)
				inRoomMusic.volume = 0;

			if(onPlayState)
			{
				StageData.loadDirectory(PlayState.SONG);
				LoadingState.loadAndSwitchState(new PlayState());
				FlxG.sound.music.volume = 0;
			}
			else MusicBeatState.switchState(new MainMenuState());
		}
		else if (controls.ACCEPT || FlxG.mouse.justPressed) 
		{
			FlxG.sound.play(Paths.sound('next'));
			openSelectedSubstate(options[curSelected]);
		}
	}
	
	function changeSelection(delta:Int = 0) {
		curSelected = FlxMath.wrap(curSelected + delta, 0, options.length - 1);

		var totalPages = Math.ceil(options.length / MAX_PER_PAGE);
		var curPage = Math.floor(curSelected / MAX_PER_PAGE);
		
		if (totalPages > 1)
			pageText.text = "Page " + (curPage + 1) + " / " + totalPages;
		else
			pageText.text = "";

		var startY = 100;
		for (num => item in grpOptions.members)
		{
			if (num >= curPage * MAX_PER_PAGE && num < (curPage + 1) * MAX_PER_PAGE)
			{
				item.visible = true;
				item.y = startY + ((num % MAX_PER_PAGE) * 35); 
				
				if (options[num] == 'Menu Music')
				{
					item.y += 50; 
				}

				if (num == curSelected)
				{
					item.color = FlxColor.WHITE;
					highlightBox.y = item.y - 4;
				}
				else
				{
					item.color = 0xFFCCCCCC; 
				}
			}
			else
			{
				item.visible = false;
			}
		}
	}

	override function destroy()
	{
		ClientPrefs.loadPrefs();
		super.destroy();
	}
}