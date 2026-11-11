package states;

import flixel.util.FlxColor;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.FlxG;
import lime.app.Application; 
import backend.Song;
import backend.Mods;

import openfl.filters.ShaderFilter;
import flixel.addons.display.FlxRuntimeShader;
#if sys
import sys.io.File;
import sys.FileSystem;
#end

using StringTools;

import mikolka.funkin.custom.mobile.MobileScaleMode;
import mikolka.vslice.ui.MainMenuState;

class CreditsState extends MusicBeatState
{
	private var grpOptions:FlxTypedGroup<FlxText>;
	private var grpRoles:FlxTypedGroup<FlxText>;
	private var grpIcons:FlxTypedGroup<FlxSprite>;
	private var pulseGroup:FlxTypedGroup<FlxSprite>;
	private var sparkleGroup:FlxTypedGroup<YasaSparkle>;

	private var itemsList:Array<FlxText> = [];
	private var rolesList:Array<FlxText> = [];
	private var iconsList:Array<FlxSprite> = [];
	private var initialYs:Array<Float> = [];
	
	private var creditsStuff:Array<Array<String>> = [];

	var mainBg:FlxSprite;
	var colorBg:FlxSprite; 
	var intendedColor:FlxColor;

	var scrollY:Float = 0;
	var targetScrollY:Float = 0;
	var maxScrollY:Float = 0;

	// Mouse Parallax & Shader Variables
	var camBG:FlxCamera;
	var camUI:FlxCamera;
	
	var curMouseX:Float = 0;
	var curMouseY:Float = 0;
	var bgBaseX:Float = 0;
	var bgBaseY:Float = 0;
	
	var shaderTime:Float = 0;
	var bgShader:FlxRuntimeShader;
	var uiShader:FlxRuntimeShader;

	var quitting:Bool = false;
	
	var yasaTextRef:FlxText = null; 

	override function create()
	{
		#if DISCORD_ALLOWED
		DiscordClient.changePresence("In the Menus", null);
		#end

		super.create(); 

		FlxG.mouse.visible = true;
		persistentUpdate = true;
		
		camBG = new FlxCamera();
		camUI = new FlxCamera();
		camUI.bgColor = 0x00000000;
		
		FlxG.cameras.reset(camBG);
		FlxG.cameras.add(camUI, false);
		FlxG.cameras.setDefaultDrawTarget(camBG, true);

		#if sys
		var shaderPath = "assets/shared/shaders/rainShader.frag"; 
		if (FileSystem.exists(shaderPath)) {
			var shaderCode = File.getContent(shaderPath);
			
			bgShader = new FlxRuntimeShader(shaderCode);
			bgShader.setFloat('cameraZoom', 1.0); 
			bgShader.setInt('STARTING_LAYERS', 1); 
			bgShader.setBool('flipY', true); 
			bgShader.setBool('pixely', false);
			bgShader.setFloat('blurStrength', 0.3);
			bgShader.setFloat('wobbleStrength', 0.25); 
			bgShader.setFloat('rainIntensity', 0.0);   
			bgShader.setFloat('opacity', 0.0);         
			camBG.filters = [new ShaderFilter(bgShader)];

			uiShader = new FlxRuntimeShader(shaderCode);
			uiShader.setFloat('cameraZoom', 10); 
			uiShader.setInt('STARTING_LAYERS', 1); 
			uiShader.setBool('flipY', true); 
			uiShader.setBool('pixely', false);
			uiShader.setFloat('blurStrength', 0.0); 
			uiShader.setFloat('wobbleStrength', 0.0); 
			uiShader.setFloat('rainIntensity', 0.0005); 
			uiShader.setFloat('opacity', 0.0005);       
			camUI.filters = [new ShaderFilter(uiShader)];
		}
		#end

		colorBg = new FlxSprite(-200, -200).makeGraphic(1, 1, FlxColor.WHITE);
		colorBg.scale.set(FlxG.width * 3, FlxG.height * 3);
		colorBg.updateHitbox();
		colorBg.scrollFactor.set(0, 0);
		colorBg.cameras = [camBG];
		add(colorBg);
		
		mainBg = new FlxSprite(0, 0);
		mainBg.loadGraphic(Paths.image('mainmenu/MainBg'));
		mainBg.antialiasing = ClientPrefs.data.antialiasing;
		mainBg.scrollFactor.set(0, 0);
		mainBg.cameras = [camBG]; 
		mainBg.setGraphicSize(FlxG.width, FlxG.height);
		mainBg.updateHitbox();
		mainBg.scale.set(1.25, 1.25); 
		mainBg.screenCenter();
		mainBg.alpha = 0.93; 
		bgBaseX = mainBg.x;
		bgBaseY = mainBg.y;
		add(mainBg);
		
		grpIcons = new FlxTypedGroup<FlxSprite>();
		grpIcons.cameras = [camUI];
		add(grpIcons);

		grpOptions = new FlxTypedGroup<FlxText>();
		grpOptions.cameras = [camUI];
		add(grpOptions);

		grpRoles = new FlxTypedGroup<FlxText>();
		grpRoles.cameras = [camUI];
		add(grpRoles);
		
		sparkleGroup = new FlxTypedGroup<YasaSparkle>();
		sparkleGroup.cameras = [camUI];
		add(sparkleGroup);

		pulseGroup = new FlxTypedGroup<FlxSprite>();
		pulseGroup.cameras = [camUI];
		add(pulseGroup);

		#if MODS_ALLOWED
		for (mod in Mods.parseList().enabled) pushModCreditsToList(mod);
		#end

		var defaultList:Array<Array<String>> = [
			['Mow Engine'],
			['Yasa', 'Yasa', 'Made Mow Engine', 'https://www.youtube.com/@Yasa_u0', 'FFFFFF'],
			[""],
			["Special Thanks"],
			["ninjamuffin99", "ninjamuffin99", "Friday Night Funkin'", "https://x.com/ninja_muffin99", "CF2D2D"],
			["Shadow Mario", "shadowmario", "Psych Engine", "https://ko-fi.com/shadowmario", "444444"],
			["Mikolka9144", "mikolka", "P-Slice Engine'", "https://gamebanana.com/members/3329541", "FFFFFF"],
			["YOU", "", "Played the mod!", "", "FFFFFF"]
		];
		for(i in defaultList) creditsStuff.push(i);
	
		var curY:Float = 100;

		for (i => credit in creditsStuff)
		{
			var isSelectable:Bool = !unselectableCheck(i);
			
			if (isSelectable) 
			{
				var nameText = new FlxText(150, 0, 0, credit[0], 52);
				
				if (credit[0].toLowerCase() == "yasa") {
					nameText.setFormat(Paths.font("Bro.TTF"), 52, FlxColor.YELLOW, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
					yasaTextRef = nameText; 
				} else {
					nameText.setFormat(Paths.font("Bro.TTF"), 52, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				}
				
				nameText.borderSize = 2.5;
				grpOptions.add(nameText);
				itemsList.push(nameText);

				var roleText = new FlxText(150, 0, 0, credit[2], 24);
				roleText.setFormat(Paths.font("Bro.TTF"), 24, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				roleText.borderSize = 1.5;
				grpRoles.add(roleText);
				rolesList.push(roleText);

				var iconSpr:FlxSprite = null;
				if(credit[1] != null && credit[1].trim().length > 0)
				{
					if(credit.length > 5 && credit[5] != null) Mods.currentModDirectory = credit[5];
					var str:String = 'credits/missing_icon';
					var fileName = 'credits/' + credit[1];
					if (Paths.fileExists('images/$fileName.png', IMAGE)) str = fileName;
					else if (Paths.fileExists('images/$fileName-pixel.png', IMAGE)) str = fileName + '-pixel';

					iconSpr = new FlxSprite().loadGraphic(Paths.image(str));
					if(str.endsWith('-pixel')) iconSpr.antialiasing = false;
					else iconSpr.antialiasing = ClientPrefs.data.antialiasing;
					
					iconSpr.scale.set(0.6, 0.6);
					iconSpr.updateHitbox();
					grpIcons.add(iconSpr);
					Mods.currentModDirectory = '';
				}
				iconsList.push(iconSpr);

				initialYs.push(curY);
				curY += nameText.height + roleText.height + 60; 
			} 
			else 
			{
				var headingText = new FlxText(80, 0, 0, credit[0], 64);
				headingText.setFormat(Paths.font("Bro.TTF"), 64, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				headingText.borderSize = 3;
				grpOptions.add(headingText);
				itemsList.push(headingText);

				rolesList.push(null);
				iconsList.push(null);
				
				initialYs.push(curY);
				
				if (credit[0] == "") curY += 40; 
				else curY += headingText.height + 40;
			}
		}
		
		maxScrollY = curY - FlxG.height + 150;
		if (maxScrollY < 0) maxScrollY = 0;

		var firstColorIdx = 0;
		while(firstColorIdx < creditsStuff.length && unselectableCheck(firstColorIdx)) firstColorIdx++;
		if(creditsStuff[firstColorIdx] != null && creditsStuff[firstColorIdx].length > 4) {
			colorBg.color = CoolUtil.colorFromString(creditsStuff[firstColorIdx][4]);
		}
		intendedColor = colorBg.color;
		
		#if TOUCH_CONTROLS_ALLOWED
		addTouchPad('UP_DOWN', 'A_B');
		#end
	}

	override function update(elapsed:Float)
	{
		shaderTime += elapsed;
		if (bgShader != null) bgShader.setFloat('time', shaderTime);
		if (uiShader != null) uiShader.setFloat('time', shaderTime);

		var targetMouseX:Float = (FlxG.mouse.x - (FlxG.width * 0.5)) / (FlxG.width * 0.5);
		var targetMouseY:Float = (FlxG.mouse.y - (FlxG.height * 0.5)) / (FlxG.height * 0.5);

		targetMouseX = FlxMath.bound(targetMouseX, -1.0, 1.0);
		targetMouseY = FlxMath.bound(targetMouseY, -1.0, 1.0);

		var lerpFactor:Float = FlxMath.bound(elapsed * 6.0, 0.0, 1.0);
		curMouseX = FlxMath.lerp(curMouseX, targetMouseX, lerpFactor);
		curMouseY = FlxMath.lerp(curMouseY, targetMouseY, lerpFactor);

		mainBg.x = bgBaseX + (curMouseX * -45);
		mainBg.y = bgBaseY + (curMouseY * -45);

		if (FlxG.sound.music != null && FlxG.sound.music.volume < 0.7) FlxG.sound.music.volume += 0.5 * FlxG.elapsed;
		
		if(!quitting)
		{
			if (controls.BACK)
			{
				FlxG.sound.play(Paths.sound('cancelMenu'));
				MusicBeatState.switchState(new MainMenuState());
				quitting = true;
			}

			var scrollDelta:Float = 0;
			var scrollSpeed:Float = 350; 
			if (FlxG.mouse.wheel != 0) {
				scrollDelta = FlxG.mouse.wheel * -120; 
			}
			if (controls.UI_UP) scrollDelta -= scrollSpeed * elapsed;
			if (controls.UI_DOWN) scrollDelta += scrollSpeed * elapsed;

			targetScrollY += scrollDelta;
			
			if (targetScrollY < 0) targetScrollY = 0;
			if (targetScrollY > maxScrollY) targetScrollY = maxScrollY;

			scrollY = FlxMath.lerp(scrollY, targetScrollY, Math.max(0, Math.min(1, elapsed * 5)));
		}

		var hoveredIndex:Int = -1;
		var mousePos = FlxG.mouse.getScreenPosition(camUI);
		var lerpVal:Float = Math.max(0, Math.min(1, elapsed * 12));
		
		for (i in 0...itemsList.length) {
			var nameText = itemsList[i];
			nameText.y = initialYs[i] - scrollY;

			var roleText = rolesList[i];
			if (roleText != null) {
				roleText.y = nameText.y + nameText.height + 2; 
			}

			var iconSpr = iconsList[i];
			if (iconSpr != null) {
				iconSpr.x = nameText.x + nameText.width + 15;
				iconSpr.y = nameText.y + (nameText.height - iconSpr.height) / 2;
			}

			if (!unselectableCheck(i)) {
				var isHovered = false;
				
				if (mousePos.x >= nameText.x - 5 && mousePos.x <= nameText.x + nameText.width + 5 &&
					mousePos.y >= nameText.y - 5 && mousePos.y <= nameText.y + nameText.height + 5) {
					isHovered = true;
				}

				if (isHovered) hoveredIndex = i;

				if (isHovered) {
					nameText.color = 0xFF00BFFF; 
				} else {
					if (creditsStuff[i][0].toLowerCase() == "yasa") {
						nameText.color = FlxColor.YELLOW;
					} else {
						nameText.color = FlxColor.WHITE;
					}
				}

				if (iconSpr != null) {
					if (isHovered) {
						iconSpr.scale.set(FlxMath.lerp(iconSpr.scale.x, 0.8, lerpVal), FlxMath.lerp(iconSpr.scale.y, 0.8, lerpVal));
						iconSpr.angle = FlxMath.lerp(iconSpr.angle, 5, lerpVal);
					} else {
						iconSpr.scale.set(FlxMath.lerp(iconSpr.scale.x, 0.6, lerpVal), FlxMath.lerp(iconSpr.scale.y, 0.6, lerpVal));
						iconSpr.angle = FlxMath.lerp(iconSpr.angle, 0, lerpVal);
					}
				}
			}
		}

		if (FlxG.mouse.justPressed && !quitting) {
			spawnDotPulse();
			if (hoveredIndex != -1) {
				var link = creditsStuff[hoveredIndex][3];
				if(link != null && link.length > 4) {
					// เอาเสียง FlxG.sound.play(Paths.sound('confirmMenu')); ออกแล้ว
					CoolUtil.browserLoad(link);
				}
			}
		}

		var centerIndex = getCenterItemIndex();
		if (centerIndex != -1 && creditsStuff[centerIndex].length > 4) {
			var newColor:FlxColor = CoolUtil.colorFromString(creditsStuff[centerIndex][4]);
			if (newColor != intendedColor) {
				intendedColor = newColor;
				FlxTween.cancelTweensOf(colorBg);
				FlxTween.color(colorBg, 1.0, colorBg.color, intendedColor, {ease: FlxEase.quadOut});
			}
		}
		
		if (!quitting && yasaTextRef != null && yasaTextRef.y > -50 && yasaTextRef.y < FlxG.height + 50) {
			if (FlxG.random.bool(10)) { 
				spawnSparkleForYasa();
			}
		}

		super.update(elapsed);
	}
	
	function spawnSparkleForYasa()
	{
		var sparkle = sparkleGroup.recycle(YasaSparkle);
		sparkle.loadGraphic(Paths.image('sparkle'));
		sparkle.antialiasing = ClientPrefs.data.antialiasing;
		sparkle.revive();
		
		sparkle.attachedText = yasaTextRef;
		
		sparkle.relativeX = FlxG.random.float(-30, yasaTextRef.width + 30);
		sparkle.relativeY = FlxG.random.float(-20, yasaTextRef.height + 20);
		
		sparkle.alpha = 0;
		sparkle.scale.set(FlxG.random.float(0.4, 1.0), FlxG.random.float(0.4, 1.0));
		
		var duration = FlxG.random.float(0.8, 1.6);
		
		FlxTween.tween(sparkle, {alpha: FlxG.random.float(0.6, 1.0)}, duration * 0.3, {
			onComplete: function(twn:FlxTween) {
				FlxTween.tween(sparkle, {alpha: 0}, duration * 0.7, {
					onComplete: function(twn:FlxTween) {
						sparkle.kill();
					}
				});
			}
		});
	}

	function spawnDotPulse()
	{
		var pulse = pulseGroup.recycle(FlxSprite);
		pulse.revive(); 

		if (pulse.frames == null) {
			pulse.frames = Paths.getSparrowAtlas('mainmenu/dotPulse');
			pulse.animation.addByPrefix('anim', 'pulse', 24, false);
			pulse.antialiasing = ClientPrefs.data.antialiasing;
		}
		
		pulse.color = FlxColor.WHITE; 
		pulse.alpha = 1.0;
		pulse.cameras = [camUI];
		
		var mousePos = FlxG.mouse.getScreenPosition(camUI);
		pulse.setPosition(mousePos.x - 20, mousePos.y - 20); 
		
		pulse.animation.play('anim', true); 
		pulse.animation.finishCallback = function(name:String) {
			pulse.kill(); 
		};
	}

	function getCenterItemIndex():Int {
		var closestDist:Float = 999999;
		var closestIndex:Int = -1;
		for (i in 0...itemsList.length) {
			if (unselectableCheck(i)) continue;
			var item = itemsList[i];
			var dist = Math.abs((item.y + item.height/2) - (FlxG.height/2));
			if (dist < closestDist) {
				closestDist = dist;
				closestIndex = i;
			}
		}
		return closestIndex;
	}

	#if MODS_ALLOWED
	function pushModCreditsToList(folder:String)
	{
		var creditsFile:String = Paths.mods(folder + '/data/credits.txt');
		#if TRANSLATIONS_ALLOWED
		var translatedCredits:String = Paths.mods(folder + '/data/credits-${ClientPrefs.data.language}.txt');
		#end

		if (#if TRANSLATIONS_ALLOWED (FileSystem.exists(translatedCredits) && (creditsFile = translatedCredits) == translatedCredits) || #end FileSystem.exists(creditsFile))
		{
			var firstarray:Array<String> = File.getContent(creditsFile).split('\n');
			for(i in firstarray)
			{
				var arr:Array<String> = i.replace('\\n', '\n').split("::");
				if(arr.length >= 5) arr.push(folder);
				creditsStuff.push(arr);
			}
			creditsStuff.push(['']);
		}
	}
	#end

	private function unselectableCheck(num:Int):Bool {
		return creditsStuff[num].length <= 1;
	}
}

class YasaSparkle extends FlxSprite 
{
	public var relativeX:Float = 0;
	public var relativeY:Float = 0;
	public var attachedText:FlxText = null;

	public function new() 
	{
		super();
	}

	override function update(elapsed:Float) 
	{
		super.update(elapsed);
		
		if (attachedText != null) {
			this.x = attachedText.x + relativeX;
			this.y = attachedText.y + relativeY;
		}
	}
}