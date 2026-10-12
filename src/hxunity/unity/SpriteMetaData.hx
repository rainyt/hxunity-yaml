package hxunity.unity;

import haxe.Int64;
import hxunity.types.VectorData;

/**
	One sprite inside a multiple-sprite texture, the entries of a `.meta` file's
	`TextureImporter.spriteSheet.sprites`:

	```yaml
	    - serializedVersion: 2
	      name: Hero_0
	      rect:
	        serializedVersion: 2
	        x: 0
	        y: 384
	        width: 128
	        height: 128
	      alignment: 0
	      pivot: {x: 0.5, y: 0.5}
	      border: {x: 0, y: 0, z: 0, w: 0}
	      ...
	      spriteID: 9d67fcc15a8c08460800000000000000
	      internalID: 7242008812290275033
	```

	`rect` is in pixels and measured **from the bottom left**, which is Unity's
	texture space and the opposite of the top-down coordinates a PSD tool works
	in; the conversion belongs to the caller, not here.

	## `internalID` and `spriteID`

	Both are optional and neither is invented. Unity assigns an
	`spriteID` (a 32 digit hash) and an `internalID` (a 63 bit number) to every
	sprite it imports, and it derives them from the sprite's name; guessing them
	would produce ids that disagree with what the editor computes, so a caller
	that has read them out of an existing `.meta` passes them through and a caller
	starting from scratch leaves them out. When [internalID] is given, the file's
	`nameFileIdTable` gets the matching entry, because that table is what
	references inside prefabs use to name a sprite of a sheet.
**/
typedef SpriteMetaData = {
	/** Sprite name, unique inside the texture. **/
	var name:String;

	/** Pixel rectangle inside the texture, bottom-left origin. **/
	var rect:{x:Int, y:Int, width:Int, height:Int};

	/** Where the pivot sits, or `null` for the settings' default. **/
	var ?pivot:VectorData;

	/** Nine-slice border `{x, y, z, w}`, or `null` for no border. **/
	var ?border:VectorData;

	/** Alignment value; `null` keeps the settings' default. **/
	var ?alignment:Int;

	/** Unity's internal id for this sprite, or `null` to let Unity assign one. **/
	var ?internalID:Int64;

	/** Unity's sprite hash, or `null` to let Unity assign one. **/
	var ?spriteID:String;
}
