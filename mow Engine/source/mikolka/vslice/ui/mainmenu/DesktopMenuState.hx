package mikolka.vslice.ui.mainmenu;

import mikolka.vslice.freeplay.FreeplayState;
import options.OptionsState;
import flixel.FlxBasic;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.effects.FlxFlicker;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import flixel.text.FlxText;
import flixel.math.FlxMath;
import objects.Alphabet; 
import lime.app.Application;

import mikolka.vslice.ui.title.TitleState;
import mikolka.vslice.ui.StoryMenuState;

import openfl.filters.ShaderFilter;
import flixel.addons.display.FlxRuntimeShader;
#if sys
import sys.io.File;
import sys.FileSystem;
#end

#if !LEGACY_PSYCH
#if MODS_ALLOWED
import states.ModsMenuState;
#end
import states.AchievementsMenuState;
import states.CreditsState;
import states.editors.MasterEditorMenu;
#else
import editors.MasterEditorMenu;
#end

import mikolka.compatibility.VsliceOptions;
using StringTools;

@:access(mikolka.vslice.ui.MainMenuState)
class DesktopMenuState extends FlxBasic
{
    var optionShit:Array<String> = [
        'Story',
        'Freeplay',
        'Credits',
        'Options'
    ];

    var itemPositions:Array<Dynamic> = [
        {x: 645, y: 75}, 
        {x: 798, y: 250}, 
        {x: 896, y: 395}, 
        {x: 896, y: 515}  
    ];

    public static var curSelected:Int = 0;
    var selectedSomethin:Bool = false;
    
    var inMainMenu:Bool = false;
    var isTransitioning:Bool = false; 
    var logoCenterX:Float;
    var joriCenterX:Float;
    
    var logoZoom:Float = 2.8; 
    var logoTargetY:Float = -850; 
    
    var joriZoom:Float = 1.6; 
    var joriTargetY:Float = 220; 
    var joriTargetX:Float = 100; 
    
    var bgZoom:Float = 1.5; 
    
    public var logoBaseX:Float;
    public var logoBaseY:Float;
    public var logoScale:Float = 1.0;
    
    public var joriBaseX:Float;
    public var joriBaseY:Float;
    
    public var bgBaseX:Float = 0;
    public var bgBaseY:Float = 0;

    var curMouseX:Float = 0;
    var curMouseY:Float = 0;

    var shaderTime:Float = 0;
    
    var bgShader:FlxRuntimeShader;
    var charShader:FlxRuntimeShader;

    var menuItems:FlxTypedGroup<FlxSprite>;
    var mainBg:FlxSprite;
    var mainLogo:FlxSprite;
    var jori:FlxSprite;
    var col:FlxSprite;
    var pulseGroup:FlxTypedGroup<FlxSprite>; 
    
    var promptText:FlxText; 
    var pulseTween:FlxTween; 
    
    var camBG:FlxCamera; 
    var camChars:FlxCamera; 
    var camUI:FlxCamera; 
    
    var introDelay:Float = 0.4;
    var host:MainMenuState;

    var colTargetX:Float = 1100; 
    
    var lastMouseX:Float = 0;
    var lastMouseY:Float = 0;
    var mouseActive:Bool = false;

    public function new(host:MainMenuState) {
        super();
        this.host = host;
        host.add(this);

        FlxG.mouse.visible = true;
        lastMouseX = FlxG.mouse.screenX;
        lastMouseY = FlxG.mouse.screenY;

        camBG = new FlxCamera();
        camBG.bgColor = 0x00000000;
        FlxG.cameras.add(camBG, false);
        
        camChars = new FlxCamera();
        camChars.bgColor = 0x00000000;
        FlxG.cameras.add(camChars, false);

        camUI = new FlxCamera();
        camUI.bgColor = 0x00000000;
        FlxG.cameras.add(camUI, false);

        #if sys
        var shaderPath = "assets/shared/shaders/rainShader.frag"; 
        if (FileSystem.exists(shaderPath)) {
            var shaderCode = File.getContent(shaderPath);
            
            // 1. Shader สำหรับพื้นหลัง (camBG) -> บิดภาพ แต่ไม่เอาฝน
            bgShader = new FlxRuntimeShader(shaderCode);
            bgShader.setFloat('cameraZoom', 1.0); 
            bgShader.setInt('STARTING_LAYERS', 1); 
            bgShader.setBool('flipY', true); 
            bgShader.setBool('pixely', false);
            bgShader.setFloat('blurStrength', 0.3);
            bgShader.setFloat('wobbleStrength', 0.25); // เปิดบิดภาพ
            bgShader.setFloat('rainIntensity', 0.0);   // ปิดฝน
            bgShader.setFloat('opacity', 0.0);         // ปิดความชัดฝน
            camBG.filters = [new ShaderFilter(bgShader)];

            // 2. Shader สำหรับตัวละครข้างหน้า (camChars) -> เอาฝน แต่ไม่บิดภาพ
            charShader = new FlxRuntimeShader(shaderCode);
            charShader.setFloat('cameraZoom', 10); 
            charShader.setInt('STARTING_LAYERS', 1); 
            charShader.setBool('flipY', true); 
            charShader.setBool('pixely', false);
            charShader.setFloat('blurStrength', 0.0); 
            charShader.setFloat('wobbleStrength', 0.0); // ปิดบิดภาพ Jori และ Logo จะไม่เบี้ยว
            charShader.setFloat('rainIntensity', 0.0005); // เปิดฝน
            charShader.setFloat('opacity', 0.0005);       // เปิดความชัดฝน
            camChars.filters = [new ShaderFilter(charShader)];
        }
        #end

        FlxG.camera.fade(FlxColor.BLACK, introDelay, true);
        camBG.fade(FlxColor.BLACK, introDelay, true);
        camChars.fade(FlxColor.BLACK, introDelay, true);
        camUI.fade(FlxColor.BLACK, introDelay, true);
        
        camBG.zoom = 2.0; 
        camChars.zoom = 2.0; 
        camUI.zoom = 2.0; 
        
        FlxTween.tween(camBG, {zoom: 1.0}, 1.0, {ease: FlxEase.expoOut, startDelay: introDelay});
        FlxTween.tween(camChars, {zoom: 1.0}, 1.0, {ease: FlxEase.expoOut, startDelay: introDelay});
        FlxTween.tween(camUI, {zoom: 1.0}, 1.0, {ease: FlxEase.expoOut, startDelay: introDelay});

        host.bg.color = 0xFF000000;
        host.bg.scrollFactor.set(0, 0);
        host.bg.updateHitbox();
        host.bg.screenCenter();

        mainBg = new FlxSprite(0, 0);
        mainBg.loadGraphic(Paths.image('mainmenu/MainBg'));
        mainBg.antialiasing = VsliceOptions.ANTIALIASING;
        mainBg.scrollFactor.set(0, 0);
        mainBg.cameras = [camBG]; 
        mainBg.setGraphicSize(FlxG.width, FlxG.height);
        mainBg.updateHitbox();
        mainBg.scale.set(1.25, 1.25); 
        mainBg.screenCenter();
        bgBaseX = mainBg.x;
        bgBaseY = mainBg.y;
        host.add(mainBg);

        mainLogo = new FlxSprite(0, 30); 
        mainLogo.loadGraphic(Paths.image('mainmenu/MainLogo'));
        mainLogo.scale.set(1.0, 1.0); 
        mainLogo.updateHitbox(); 
        logoCenterX = (FlxG.width - mainLogo.width) / 2; 
        logoBaseX = logoCenterX;
        logoBaseY = 30;
        mainLogo.antialiasing = VsliceOptions.ANTIALIASING;
        mainLogo.scrollFactor.set(0, 0);
        mainLogo.cameras = [camChars]; 
        host.add(mainLogo);

        jori = new FlxSprite(0, 30); 
        jori.loadGraphic(Paths.image('mainmenu/Jori'));
        jori.scale.set(1.0, 1.0); 
        jori.updateHitbox(); 
        joriCenterX = ((FlxG.width - jori.width) / 2) - 80; 
        joriBaseX = joriCenterX;
        joriBaseY = 30;
        jori.antialiasing = VsliceOptions.ANTIALIASING;
        jori.scrollFactor.set(0, 0);
        jori.cameras = [camChars]; 
        host.add(jori);

        col = new FlxSprite(FlxG.width + 400, 0); 
        col.loadGraphic(Paths.image('mainmenu/Col'));
        col.antialiasing = VsliceOptions.ANTIALIASING;
        col.scrollFactor.set(0, 0);
        col.cameras = [camUI]; 
        col.setGraphicSize(Std.int(col.width), FlxG.height);
        col.updateHitbox();
        host.add(col);

        menuItems = new FlxTypedGroup<FlxSprite>();
        host.add(menuItems);

        for (i in 0...optionShit.length)
        {
            var menuItem:FlxSprite = new FlxSprite(FlxG.width + 400, itemPositions[i].y); 
            menuItem.antialiasing = VsliceOptions.ANTIALIASING;
            menuItem.cameras = [camUI]; 
            
            changeItemGraphic(menuItem, optionShit[i]);
            menuItems.add(menuItem);
            menuItem.scrollFactor.set(0, 0);
        }

        promptText = new FlxText(0, FlxG.height - 30, 0, "Click or Enter to open menu", 28);
        promptText.setFormat(Paths.font("vcr.ttf"), 28, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
        promptText.screenCenter(X);
        promptText.cameras = [camUI]; 
        host.add(promptText);

        pulseGroup = new FlxTypedGroup<FlxSprite>();
        pulseGroup.cameras = [camUI];
        host.add(pulseGroup);

        pulseTween = FlxTween.tween(promptText, {alpha: 0.15}, 1.5, {type: PINGPONG, ease: FlxEase.sineInOut});

        changeItem(0, true);

        #if TOUCH_CONTROLS_ALLOWED
        host.addTouchPad('UP_DOWN', 'A_B');
        #end
    }

    override function update(elapsed:Float)
    {
        shaderTime += elapsed;
        
        if (bgShader != null) bgShader.setFloat('time', shaderTime);
        if (charShader != null) charShader.setFloat('time', shaderTime);

        // เช็คการขยับหรือคลิกเมาส์
        if (Math.abs(FlxG.mouse.screenX - lastMouseX) > 2 || Math.abs(FlxG.mouse.screenY - lastMouseY) > 2 || FlxG.mouse.justPressed) {
            mouseActive = true;
        }
        lastMouseX = FlxG.mouse.screenX;
        lastMouseY = FlxG.mouse.screenY;

        if (FlxG.mouse.justPressed) {
            spawnDotPulse();
        }

        var targetMouseX:Float = (FlxG.mouse.x - (FlxG.width * 0.5)) / (FlxG.width * 0.5);
        var targetMouseY:Float = (FlxG.mouse.y - (FlxG.height * 0.5)) / (FlxG.height * 0.5);

        targetMouseX = FlxMath.bound(targetMouseX, -1.0, 1.0);
        targetMouseY = FlxMath.bound(targetMouseY, -1.0, 1.0);

        var lerpFactor:Float = FlxMath.bound(elapsed * 6.0, 0.0, 1.0);
        curMouseX = FlxMath.lerp(curMouseX, targetMouseX, lerpFactor);
        curMouseY = FlxMath.lerp(curMouseY, targetMouseY, lerpFactor);

        var floatOffsetY = Math.sin(shaderTime * 1.2) * 12;
        var floatAngle = Math.sin(shaderTime * 0.8) * 3;

        mainBg.x = bgBaseX + (curMouseX * -45);
        mainBg.y = bgBaseY + (curMouseY * -45);

        mainLogo.x = logoBaseX + (curMouseX * -25);
        mainLogo.y = logoBaseY + floatOffsetY + (curMouseY * -25);
        mainLogo.angle = floatAngle;
        mainLogo.scale.set(logoScale, logoScale); 

        jori.x = joriBaseX + (curMouseX * -10);
        jori.y = joriBaseY + (curMouseY * -10);

        if (!selectedSomethin && !isTransitioning)
        {
            if (!inMainMenu) 
            {
                if (host.controls.ACCEPT || FlxG.mouse.justPressed)
                {
                    openMenu(); 
                }
            } 
            else 
            {
                var mouseOverMenu = false;
                var hoveredIndex = -1;
                
                if (mouseActive) {
                    var mousePos = FlxG.mouse.getScreenPosition(camUI);
                    for (i in 0...menuItems.members.length) {
                        var item = menuItems.members[i];
                        if (item != null && item.visible) {
                            if (mousePos.x >= item.x && mousePos.x <= item.x + item.width &&
                                mousePos.y >= item.y && mousePos.y <= item.y + item.height) {
                                mouseOverMenu = true;
                                hoveredIndex = i;
                                break; 
                            }
                        }
                    }
                }

                if (hoveredIndex != -1 && curSelected != hoveredIndex) {
                    changeItem(hoveredIndex - curSelected);
                }

                if (host.controls.UI_UP_P) {
                    changeItem(-1);
                    mouseActive = false; 
                }
                if (host.controls.UI_DOWN_P) {
                    changeItem(1);
                    mouseActive = false; 
                }

                if (host.controls.BACK)
                {
                    closeMenu(); 
                }

                var mouseClicked = mouseOverMenu && FlxG.mouse.justPressed;

                if (host.controls.ACCEPT || mouseClicked)
                {
                    FlxG.sound.play(Paths.sound('confirmMenu'));
                    FlxTransitionableState.skipNextTransIn = false;
                    FlxTransitionableState.skipNextTransOut = false;
                    selectedSomethin = true;

                    FlxG.camera.flash(0x66FFFFFF, 0.5); 
                    camBG.flash(0x66FFFFFF, 0.5);
                    camChars.flash(0x66FFFFFF, 0.5);
                    camUI.flash(0x66FFFFFF, 0.5);
                    camUI.shake(0.008, 0.2); 

                    var outSpeed:Float = 1.0; 
                    
                    FlxTween.tween(this, {logoBaseY: -850}, outSpeed, {ease: FlxEase.cubeIn, startDelay: 0.0});
                    FlxTween.tween(this, {joriBaseX: -800}, outSpeed, {ease: FlxEase.cubeIn, startDelay: 0.1});
                    FlxTween.tween(col, {x: FlxG.width + 400}, outSpeed, {ease: FlxEase.cubeIn, startDelay: 0.1});
                    
                    for (i in 0...menuItems.members.length) {
                        FlxTween.tween(menuItems.members[i], {x: FlxG.width + 400}, outSpeed, {ease: FlxEase.cubeIn, startDelay: 0.05 + (i * 0.05)});
                    }

                    new FlxTimer().start(0.2, function(tmr:FlxTimer) {
                        FlxTween.tween(camBG, {zoom: 2.0}, 1.0, {ease: FlxEase.sineIn});
                        FlxTween.tween(camChars, {zoom: 2.0}, 1.0, {ease: FlxEase.sineIn});
                        FlxTween.tween(camUI, {zoom: 2.0}, 1.0, {ease: FlxEase.sineIn});
                        
                        FlxG.camera.fade(FlxColor.BLACK, 1.0, false);
                        camBG.fade(FlxColor.BLACK, 1.0, false);
                        camChars.fade(FlxColor.BLACK, 1.0, false);
                        camUI.fade(FlxColor.BLACK, 1.0, false);
                    });

                    var toggled:Bool = false;
                    new FlxTimer().start(0.06, function(tmr:FlxTimer) {
                        toggled = !toggled;
                        var currentItem = menuItems.members[curSelected];
                        if(toggled) changeItemGraphic(currentItem, optionShit[curSelected] + 'Idle');
                        else changeItemGraphic(currentItem, optionShit[curSelected] + 'Conf');
                    }, 15);

                    new FlxTimer().start(1.4, function(tmr:FlxTimer) {
                        switch (optionShit[curSelected])
                        {
                            case 'Story': MusicBeatState.switchState(new StoryMenuState());
                            case 'Freeplay':
                                var freeplaySub = new FreeplayState();
                                freeplaySub.closeCallback = restoreMenu;
                                host.openSubState(freeplaySub);
                            case 'Credits': MusicBeatState.switchState(new CreditsState());
                            case 'Options': host.goToOptions();
                        }
                    });
                }

                if (#if LEGACY_PSYCH FlxG.keys.anyJustPressed(ClientPrefs.keyBinds.get('debug_1').filter(s -> s != -1)) #else host.controls.justPressed('debug_1') #end)
                {
                    selectedSomethin = true;
                    MusicBeatState.switchState(new MasterEditorMenu());
                }
            }
        }
        super.update(elapsed);
    }

    function spawnDotPulse()
    {
        var pulse = pulseGroup.recycle(FlxSprite);
        pulse.revive(); 

        if (pulse.frames == null) {
            pulse.frames = Paths.getSparrowAtlas('mainmenu/dotPulse');
            pulse.animation.addByPrefix('anim', 'pulse', 24, false);
            pulse.antialiasing = VsliceOptions.ANTIALIASING;
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

    function openMenu()
    {
        inMainMenu = true;
        isTransitioning = true;
        
        var animSpeed:Float = 1.8;
        var easeFunc = FlxEase.quintOut;

        FlxTween.tween(this, {logoScale: logoZoom}, animSpeed, {ease: easeFunc});
        FlxTween.tween(this, {logoBaseY: logoTargetY}, animSpeed, {ease: easeFunc});
        
        FlxTween.tween(this, {joriBaseX: joriTargetX, joriBaseY: joriTargetY}, animSpeed, {ease: easeFunc});
        FlxTween.tween(jori.scale, {x: joriZoom, y: joriZoom}, animSpeed, {ease: easeFunc});
        FlxTween.tween(mainBg.scale, {x: bgZoom, y: bgZoom}, animSpeed, {ease: easeFunc});

        if (pulseTween != null) pulseTween.cancel();
        FlxTween.tween(promptText, {y: FlxG.height + 50, alpha: 0}, 1.0, {ease: easeFunc});

        FlxTween.tween(col, {x: colTargetX}, animSpeed, {ease: easeFunc});
        for (i in 0...menuItems.members.length) {
            FlxTween.tween(menuItems.members[i], {x: itemPositions[i].x}, animSpeed, {ease: easeFunc, startDelay: 0.05 * i});
        }

        new FlxTimer().start(animSpeed + 0.1, function(tmr:FlxTimer) {
            isTransitioning = false;
        });
    }

    function closeMenu()
    {
        inMainMenu = false;
        isTransitioning = true;
        
        var animSpeed:Float = 1.8;
        var easeFunc = FlxEase.quintOut;

        FlxTween.tween(this, {logoScale: 1.0, logoBaseY: 30}, animSpeed, {ease: easeFunc});
        FlxTween.tween(this, {joriBaseX: joriCenterX, joriBaseY: 30}, animSpeed, {ease: easeFunc});
        FlxTween.tween(jori.scale, {x: 1.0, y: 1.0}, animSpeed, {ease: easeFunc});
        FlxTween.tween(mainBg.scale, {x: 1.25, y: 1.25}, animSpeed, {ease: easeFunc}); 

        FlxTween.tween(promptText, {y: FlxG.height - 30, alpha: 1.0}, animSpeed, {ease: easeFunc, onComplete: function(twn:FlxTween) {
            pulseTween = FlxTween.tween(promptText, {alpha: 0.15}, 1.5, {type: PINGPONG, ease: FlxEase.sineInOut});
        }});

        FlxTween.tween(col, {x: FlxG.width + 400}, animSpeed, {ease: easeFunc});
        for (i in 0...menuItems.members.length) {
            FlxTween.tween(menuItems.members[i], {x: FlxG.width + 400}, animSpeed, {ease: easeFunc, startDelay: 0.05 * i});
        }

        new FlxTimer().start(animSpeed + 0.1, function(tmr:FlxTimer) {
            isTransitioning = false; 
        });
    }

    public function restoreMenu()
    {
        selectedSomethin = false;
        isTransitioning = false;
        inMainMenu = false; 

        FlxG.camera.fade(FlxColor.BLACK, introDelay, true);
        camBG.fade(FlxColor.BLACK, introDelay, true);
        camChars.fade(FlxColor.BLACK, introDelay, true);
        camUI.fade(FlxColor.BLACK, introDelay, true);
        
        camBG.zoom = 2.0; 
        camChars.zoom = 2.0; 
        camUI.zoom = 2.0; 
        
        FlxTween.tween(camBG, {zoom: 1.0}, 1.0, {ease: FlxEase.expoOut});
        FlxTween.tween(camChars, {zoom: 1.0}, 1.0, {ease: FlxEase.expoOut});
        FlxTween.tween(camUI, {zoom: 1.0}, 1.0, {ease: FlxEase.expoOut});

        mainBg.scale.set(1.25, 1.25);
        mainBg.screenCenter();
        bgBaseX = mainBg.x;
        bgBaseY = mainBg.y;
        
        logoScale = 1.0;
        logoBaseX = logoCenterX;
        logoBaseY = 30;

        jori.scale.set(1.0, 1.0);
        joriBaseX = joriCenterX;
        joriBaseY = 30;

        promptText.y = FlxG.height - 30;
        promptText.alpha = 1.0;
        if (pulseTween != null) pulseTween.cancel();
        pulseTween = FlxTween.tween(promptText, {alpha: 0.15}, 1.5, {type: PINGPONG, ease: FlxEase.sineInOut});

        col.x = FlxG.width + 400;

        for (i in 0...menuItems.members.length) {
            menuItems.members[i].x = FlxG.width + 400;
        }

        changeItem(0, true);
    }

    function changeItem(huh:Int = 0, isInit:Bool = false)
    {
        if (huh != 0 && !isInit)
            FlxG.sound.play(Paths.sound('scrollMenu'));

        curSelected += huh;
        if (curSelected >= menuItems.length) curSelected = 0;
        if (curSelected < 0) curSelected = menuItems.length - 1;

        for (i in 0...menuItems.members.length) {
            if (i == curSelected) {
                changeItemGraphic(menuItems.members[i], optionShit[i] + 'Idle');
            } else {
                changeItemGraphic(menuItems.members[i], optionShit[i]);
            }
            menuItems.members[i].centerOffsets();
        }
    }

    function changeItemGraphic(item:FlxSprite, graphicName:String)
    {
        item.loadGraphic(Paths.image('mainmenu/' + graphicName));
        item.scale.set(1.0, 1.0); 
        item.updateHitbox(); 
    }
}