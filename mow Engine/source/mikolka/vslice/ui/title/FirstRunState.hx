package mikolka.vslice.ui.title;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import backend.ClientPrefs;

enum SetupStage {
    ASK_RESET;
    CONFIRM_NO;
}

class FirstRunState extends flixel.FlxState
{
    var titleText:FlxText;
    var bodyText:FlxText;
    var hintText:FlxText;
    
    var currentStage:SetupStage = ASK_RESET;
    var isTransitioning:Bool = false;

    override public function create():Void
    {
        super.create();

        // เช็คว่าเคยผ่านหน้านี้หรือยัง
        if (FlxG.save.data.seenFirstRun != null && FlxG.save.data.seenFirstRun == true) {
            FlxG.switchState(new WarningState());
            return;
        }

        var bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
        add(bg);

        titleText = new FlxText(0, 100, FlxG.width, "INITIAL SETUP", 72);
        titleText.setFormat(Paths.font("vcr.ttf"), 84, FlxColor.YELLOW, CENTER, OUTLINE, FlxColor.BLACK);
        titleText.borderSize = 4;
        add(titleText);

        bodyText = new FlxText(0, 0, FlxG.width * 0.9, "", 38);
        bodyText.setFormat(Paths.font("vcr.ttf"), 38, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
        bodyText.screenCenter(XY);
        add(bodyText);

        hintText = new FlxText(0, FlxG.height - 100, FlxG.width, "", 26);
        hintText.setFormat(Paths.font("vcr.ttf"), 26, FlxColor.CYAN, CENTER, OUTLINE, FlxColor.BLACK);
        add(hintText);

        updateDisplay();
    }

    function updateDisplay() {
        switch (currentStage) {
            case ASK_RESET:
                bodyText.text = "Would you like to reset all game settings\nto their default values?\n(Graphics, Gameplay, and Controls)";
                hintText.text = "[Y] YES, RESET EVERYTHING  |  [N] NO, KEEP SETTINGS";
            case CONFIRM_NO:
                bodyText.text = "ARE YOU SURE?\nYour current settings will be kept.";
                hintText.text = "[Y] I AM SURE  |  [N] GO BACK";
        }
        bodyText.screenCenter(XY);
        bodyText.y += 30;
    }

    override function update(elapsed:Float)
    {
        super.update(elapsed);

        if (isTransitioning) return;

        if (currentStage == ASK_RESET) {
            if (FlxG.keys.justPressed.Y) {
                resetEverything(); 
                proceed();
            } else if (FlxG.keys.justPressed.N) {
                currentStage = CONFIRM_NO;
                updateDisplay();
            }
        } 
        else if (currentStage == CONFIRM_NO) {
            if (FlxG.keys.justPressed.Y) {
                proceed(); 
            } else if (FlxG.keys.justPressed.N) {
                currentStage = ASK_RESET; 
                updateDisplay();
            }
        }
    }

    function resetEverything() {
        try {
            trace("Hard Reset: Wiping everything...");

            // 1. ล้างข้อมูลดิบในเซฟ
            if (FlxG.save.data != null) {
                FlxG.save.data.settings = null;
                FlxG.save.data.controls = null;
                FlxG.save.data.customControls = null;
            }

            // 2. โหลดค่ามาตรฐานใหม่
            if (Reflect.hasField(ClientPrefs, "loadPrefs")) {
                ClientPrefs.loadPrefs();
            }

            // 3. รีเซ็ตปุ่มกด (แก้ไขชื่อฟังก์ชันเป็น loadDefaultKeys ตาม Error)
            if (Reflect.hasField(ClientPrefs, "loadDefaultKeys")) {
                ClientPrefs.loadDefaultKeys();
            }
            
            // 4. บันทึกและเคลียร์ Cache
            ClientPrefs.saveSettings();
            FlxG.save.flush();

            trace("Reset complete.");
        } catch(e:Dynamic) {
            trace("Error during reset: " + e);
        }
    }

    function proceed() {
        isTransitioning = true;
        FlxG.save.data.seenFirstRun = true;
        FlxG.save.flush();
        
        var overlay = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
        overlay.alpha = 0;
        add(overlay);
        
        FlxTween.tween(overlay, {alpha: 1}, 0.6, {onComplete: function(twn:FlxTween) {
            FlxG.switchState(new WarningState()); 
        }});
    }
}