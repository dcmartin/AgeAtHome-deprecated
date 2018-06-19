#!/bin/csh -fb
set file = $1
set class = $2
set crop = $3

setenv DEBUG true
setenv VERBOSE true

if ($?CAMERA_IMAGE_WIDTH == 0) setenv CAMERA_IMAGE_WIDTH 640
if ($?CAMERA_IMAGE_HEIGHT == 0) setenv CAMERA_IMAGE_HEIGHT 480
if ($?MODEL_IMAGE_WIDTH == 0) setenv MODEL_IMAGE_WIDTH 224
if ($?MODEL_IMAGE_HEIGHT == 0) setenv MODEL_IMAGE_HEIGHT 224
if ($?CAMERA_MODEL_TRANSFORM == 0) setenv CAMERA_MODEL_TRANSFORM "CROP"

if (! -e "$file") then
  if ($?DEBUG) echo "$0:t $$ -- NO FILE ($file)" >&! /dev/stderr
  exit(1) 
else
  if ($?DEBUG) echo "$0:t $$ -- FILE ($file) ($class) ($crop)" >&! /dev/stderr
endif

switch ($file:e)
    case "jpeg": # 224x224 image
	set csize = "200x20"
	set psize = "18"
      breaksw
    case "jpg": # 640x480 image
    default:
      set csize = "600x40"
      set psize = "48"
      breaksw
endsw

set out = "$file:r.$$.$file:e"

set xywh = ( `echo "$crop" | sed "s/\(.*\)x\(.*\)\([+-]\)\(.*\)\([+-]\)\(.*\)/\3\4 \5\6 \1 \2/"` )
if ($?xywh == 0) then
  if ($?DEBUG) echo "$0:t $$ -- BAD CROP ($crop)" >&! /dev/stderr
  exit(1)
else if ($#xywh != 4) then
  if ($?DEBUG) echo "$0:t $$ -- INVALID CROP ($crop) ($xywh)" >&! /dev/stderr
  exit(1)
else
  if ($?DEBUG) echo "$0:t $$ -- GOOD CROP ($crop) ($xywh)" >&! /dev/stderr
endif


if ($file:e == "jpg") then

  set x = `echo "0 $xywh[1]" | bc`
  if ($?x == 0) @ x = 0
  if ($#x == 0) @ x = 0
  if ($x < 0 || $x > $CAMERA_IMAGE_WIDTH) @ x = 0
  set y = `echo "0 $xywh[2]" | bc`
  if ($?y == 0) @ y = 0
  if ($#y == 0) @ y = 0
  if ($y < 0 || $y > $CAMERA_IMAGE_HEIGHT) @ y = 0
  set w = $xywh[3]
  if ($?w == 0) @ w = $CAMERA_IMAGE_WIDTH
  if ($w <= 0 || $w > $CAMERA_IMAGE_WIDTH) @ w = $CAMERA_IMAGE_WIDTH
  set h = $xywh[4]
  if ($?h == 0) @ h = $CAMERA_IMAGE_HEIGHT
  if ($h <= 0 || $h > $CAMERA_IMAGE_HEIGHT) @ h = $CAMERA_IMAGE_HEIGHT

  @ ew = $x + $w
  @ eh = $y + $h
  set target = ( $x $y $ew $eh )

  if ($?DEBUG) echo "$0:t $$ -- FILE ($file) ($x $y $w $h)" >&! /dev/stderr

  # calculate centroid of movement bounding box
  @ cx = `echo "$x + ( $w / 2 )" | bc`
  @ cy = $y + ( $h / 2 )

  if ($?DEBUG) echo "$0:t $$ -- Centroid ($cx $cy) Extant ($w $h)" >&! /dev/stderr

  # subtract off half of model size
  @ sx = $cx - ( $MODEL_IMAGE_WIDTH / 2 )
  if ($sx < 0) @ sx = 0
  @ sy = $cy - ( $MODEL_IMAGE_HEIGHT / 2 )
  if ($sy < 0) @ sy = 0
  # adjust for scale
  @ sw = $MODEL_IMAGE_WIDTH
  @ sh = $MODEL_IMAGE_HEIGHT
  # adjust if past edge
  if ($sx + $sw > $CAMERA_IMAGE_WIDTH) @ sx = $CAMERA_IMAGE_WIDTH - $sw
  if ($sy + $sh > $CAMERA_IMAGE_HEIGHT) @ sy = $CAMERA_IMAGE_HEIGHT - $sh

  if ($?DEBUG) echo "$0:t $$ -- Start ($sx $sy) Extant ($sw $sh)" >&! /dev/stderr

  # cropped rectangle of MODEL_IMAGE_WIDTH x MODEL_IMAGE_HEIGHT
  @ rw = $sx + $sw
  @ rh = $sy + $sh
  set rect = ( $sx $sy $rw $rh )

  set xform = "$sw"x"$sh"+"$sx"+"$sy"

  if ($?DEBUG) echo "$0:t $$ -- Rect ($rect) Xform ($xform)" >&! /dev/stderr
  if ($?CAMERA_MODEL_TRANSFORM) then
    switch ($CAMERA_MODEL_TRANSFORM)
      case "RESIZE":
        breaksw
      case "CROP":
        set cropped = "$file:r.$$.jpeg"
        convert \
 	  -crop "$xform" "$file" \
	  -gravity center \
	  -background gray \
          "$cropped"
        if (-e "$cropped") then
          set random = "$cropped:r.random.jpeg"
          convert -size "$CAMERA_IMAGE_WIDTH"'x'"$CAMERA_IMAGE_HEIGHT" 'xc:' '+noise' Random "$random"
          if (-e "$random") then
            set composed = "$file:r.jpeg"
            composite -compose src -geometry +"$sx"+"$sy" "$cropped" "$random" "$composed"
            if (! -e "$composed") unset composed
            /bin/rm -f "$random" "$cropped"
          else
            if ($?DEBUG) echo "$0:t $$ -- $random failed" >&! /dev/stderr
          endif
          if ($?composed) then
            if ($?DEBUG) echo "$0:t $$ -- SUCCESS composed ($composed)" >&! /dev/stderr
          else
            if ($?DEBUG) echo "$0:t $$ -- FAILURE composing" >&! /dev/stderr
          endif
        else
          if ($?DEBUG) echo "$0:t $$ -- FAILURE TO CROP ($cropped)" >&! /dev/stderr
        endif
        breaksw
      default:
        if ($?DEBUG) echo "$0:t $$ -- invalid CAMERA_MODEL_TRANSFORM ($CAMERA_MODEL_TRANSFORM)" >&! /dev/stderr
        breaksw
  endsw
else
  if ($?DEBUG) echo "$0:t $$ -- no CAMERA_MODEL_TRANSFORM specified" >&! /dev/stderr
endif

if ($?IMAGE_ANNOTATE_TEXT) then
  if ($?IMAGE_ANNOTATE_FONT == 0) then
    set fonts = ( `convert -list font | awk -F': ' '/glyphs/ { print $2 }' | sort | uniq` )
    if ($#fonts == 0) then
      if ($?DEBUG) echo "$0:t $$ -- found no fonts using convert(1) to list fonts" >&! /dev/stderr
      set fonts = ( `fc-list | awk -F: '{ print $1 }' | sort | uniq` )
      if ($#fonts == 0) then
        if ($?DEBUG) echo "$0:t $$ -- found no fonts using fc-list(1) to list fonts" >&! /dev/stderr
      endif 
    endif
    # use the first font
    if ($#fonts) set font = $fonts[1]
  else
    set font = "$IMAGE_ANNOTATE_FONT"
  endif
  if ($?font) then
    # attempt to write the "$class" annotation
    convert \
      -font "$font" \
      -pointsize "$psize" -size "$csize" xc:none -gravity center -stroke black -strokewidth 2 -annotate 0 "$class" \
      -background none -shadow "100x3+0+0" +repage -stroke none -fill white -annotate 0 "$class" \
      "$file" \
      +swap -gravity south -geometry +0-3 -composite -fill none -stroke white -strokewidth 3 -draw "rectangle $rect" \
      "$out" >&! /dev/stderr
  endif
endif

if (-e "$out") then
  if ($?DEBUG) echo "$0:t $$ -- trying to convert $file into $out" >&! /dev/stderr
  convert "$out" -fill none -stroke red -strokewidth 3 -draw "rectangle $target" "$out.$$" >&! /dev/stderr
  mv "$out.$$" "$out"
endif

if (-e "$out") then
  if ($?DEBUG) echo "$0:t ($$) -- OUTPUT SUCCESSFUL $out ($class $rect)" >&! /dev/stderr
  /bin/dd if="$out"
  /bin/rm -f "$out"
  exit 0
else if (-e "$file") then
  if ($?DEBUG) echo "$0:t ($$) -- OUTPUT FAILURE $out (returning $file)" >&! /dev/stderr
  /bin/dd if="$file"
  /bin/rm -f "$out"
  exit 1
else if (! -e "$file") then
  if ($?DEBUG) echo "$0:t ($$) -- NO INPUT ($file)" >&! /dev/stderr
  /bin/rm -f "$out"
  exit 1
endif
