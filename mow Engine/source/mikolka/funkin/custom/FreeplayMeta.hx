package mikolka.funkin.custom;

import haxe.Json;


class FreeplayMetaJSON {
    public function new() {}
    public var songRating:Int = -1;
    public var allowNewTag:Bool = false;
    public var allowErectVariants:Bool = false;
    public var freeplayPrevStart:Float = 0; // those are in seconds btw
    public var freeplayPrevEnd:Float = 0.2;// and this too
    public var freeplaySongLength:Float = 1;// and this too
    public var freeplayCharacter:String = "";
    public var albumId:String = "";
    public var altInstrumentalSongs:String = "";
    public var freeplayWeekName:String = "";
    /**
     * Optional per-beat camera zoom increment for freeplay preview (same units as chart "Add Camera Zoom" value 1).
     * When set and > 0, overrides parsing the chart for a custom increment.
     */
    public var freeplayBeatCamZoom:Null<Float> = null;
}

class FreeplayMeta {
    public static function getMeta(songId:String):FreeplayMetaJSON {
        var meta_file = Paths.getTextFromFile('data/${Paths.formatToSongPath(songId)}/metadata.json');
        if(meta_file != null){
            return getMetaFile(meta_file);
        }
        else {
            return new FreeplayMetaJSON();
        }
    }
    private static function getMetaFile(rawJson:String):FreeplayMetaJSON {

        try {
            if(rawJson != null && rawJson.length > 0) {
                return new FreeplayMetaJSON().mergeWithJson(Json.parse(rawJson));
            }
        }
        catch(x){
            trace("Malfolded json? tf did you do to it?");
            trace(x.message);
        }
		
		return new FreeplayMetaJSON();
	}
}