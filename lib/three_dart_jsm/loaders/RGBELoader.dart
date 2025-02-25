part of jsm_loader;

// https://github.com/mrdoob/three.js/issues/5552
// http://en.wikipedia.org/wiki/RGBE_image_format

class RGBELoader extends DataTextureLoader {
  int type = HalfFloatType;

  RGBELoader([manager]) : super(manager) {}

  // adapted from http://www.graphics.cornell.edu/~bjw/rgbe.html

  parse(buffer, [String? path, Function? onLoad, Function? onError]) {
    int byteArrayPos = 0;

    const
        /* return codes for rgbe routines */
        //RGBE_RETURN_SUCCESS = 0,
        RGBE_RETURN_FAILURE = -1,

        /* default error routine.  change this to change error handling */
        rgbe_read_error = 1,
        rgbe_write_error = 2,
        rgbe_format_error = 3,
        rgbe_memory_error = 4;

    var rgbe_error = (rgbe_error_code, msg) {
      switch (rgbe_error_code) {
        case rgbe_read_error:
          print('THREE.RGBELoader Read Error: ${msg ?? ""}');
          break;
        case rgbe_write_error:
          print('THREE.RGBELoader Write Error: ${msg ?? ""}');
          break;
        case rgbe_format_error:
          print('THREE.RGBELoader Bad File Format: ${msg ?? ""}');
          break;
        case rgbe_memory_error:
          print('THREE.RGBELoader: Error: ${msg ?? ""}');
          break;
        default:
      }

      return RGBE_RETURN_FAILURE;
    };

    /* offsets to red, green, and blue components in a data (float) pixel */
    //RGBE_DATA_RED = 0,
    //RGBE_DATA_GREEN = 1,
    //RGBE_DATA_BLUE = 2,

    /* number of floats per pixel, use 4 since stored in rgba image format */
    //RGBE_DATA_SIZE = 4,

    /* flags indicating which fields in an rgbe_header_info are valid */
    var RGBE_VALID_PROGRAMTYPE = 1,
        RGBE_VALID_FORMAT = 2,
        RGBE_VALID_DIMENSIONS = 4;

    var NEWLINE = '\n';

    var fgets = (Uint8List buffer, [lineLimit, consume]) {
      var chunkSize = 128;

      lineLimit = lineLimit == null ? 1024 : lineLimit;
      var p = byteArrayPos;
      var i = -1;
      int len = 0;
      var s = '';
      var chunk = String.fromCharCodes(buffer.sublist(p, p + chunkSize));

      while ((0 > (i = chunk.indexOf(NEWLINE))) &&
          (len < lineLimit) &&
          (p < buffer.lengthInBytes)) {
        s += chunk;
        len += chunk.length;
        p += chunkSize;
        chunk += String.fromCharCodes(buffer.sublist(p, p + chunkSize));
      }

      if (-1 < i) {
        /*for (i=l-1; i>=0; i--) {
						byteCode = m.charCodeAt(i);
						if (byteCode > 0x7f && byteCode <= 0x7ff) byteLen++;
						else if (byteCode > 0x7ff && byteCode <= 0xffff) byteLen += 2;
						if (byteCode >= 0xDC00 && byteCode <= 0xDFFF) i--; //trail surrogate
					}*/
        if (false != consume) byteArrayPos += len + i + 1;
        return s + chunk.substring(0, i);
      }

      return null;
    };

    /* minimal header reading.  modify if you want to parse more information */
    var RGBE_ReadHeader = (buffer) {
      // regexes to parse header info fields
      var magic_token_re = RegExp(r"^#\?(\S+)"),
          gamma_re = RegExp(r"^\s*GAMMA\s*=\s*(\d+(\.\d+)?)\s*$"),
          exposure_re = RegExp(r"^\s*EXPOSURE\s*=\s*(\d+(\.\d+)?)\s*$"),
          format_re = RegExp(r"^\s*FORMAT=(\S+)\s*$"),
          dimensions_re = RegExp(r"^\s*\-Y\s+(\d+)\s+\+X\s+(\d+)\s*$");

      // RGBE format header struct
      Map<String, dynamic> header = {
        "valid": 0,
        /* indicate which fields are valid */

        "string": '',
        /* the actual header string */

        "comments": '',
        /* comments found in header */

        "programtype": 'RGBE',
        /* listed at beginning of file to identify it after "#?". defaults to "RGBE" */

        "format": '',
        /* RGBE format, default 32-bit_rle_rgbe */

        "gamma": 1.0,
        /* image has already been gamma corrected with given gamma. defaults to 1.0 (no correction) */

        "exposure": 1.0,
        /* a value of 1.0 in an image corresponds to <exposure> watts/steradian/m^2. defaults to 1.0 */

        "width": 0,
        "height": 0 /* image dimensions, width/height */
      };

      var match;

      var line = fgets(buffer, null, null);

      if (byteArrayPos >= buffer.lengthInBytes || line == null) {
        return rgbe_error(rgbe_read_error, 'no header found');
      }

      /* if you want to require the magic token then uncomment the next line */
      if (!(magic_token_re.hasMatch(line))) {
        return rgbe_error(rgbe_format_error, 'bad initial token');
      }

      match = magic_token_re.firstMatch(line);

      int _valid = header["valid"]!;

      _valid |= RGBE_VALID_PROGRAMTYPE;
      header["valid"] = _valid;

      header["programtype"] = match[1];
      header["string"] += line + '\n';

      while (true) {
        line = fgets(buffer);
        if (null == line) break;
        header["string"] += line + '\n';

        if (line.length > 0 && '#' == line[0]) {
          header["comments"] += line + '\n';
          continue; // comment line

        }

        if (gamma_re.hasMatch(line)) {
          match = gamma_re.firstMatch(line);

          header["gamma"] = parseFloat(match[1]);
        }

        if (exposure_re.hasMatch(line)) {
          match = exposure_re.firstMatch(line);

          header["exposure"] = parseFloat(match[1]);
        }

        if (format_re.hasMatch(line)) {
          match = format_re.firstMatch(line);

          header["valid"] |= RGBE_VALID_FORMAT;
          header["format"] = match[1]; //'32-bit_rle_rgbe';

        }

        if (dimensions_re.hasMatch(line)) {
          match = dimensions_re.firstMatch(line);

          header["valid"] |= RGBE_VALID_DIMENSIONS;
          header["height"] = int.parse(match[1]);
          header["width"] = int.parse(match[2]);
        }

        if ((header["valid"] & RGBE_VALID_FORMAT) == 1 &&
            (header["valid"] & RGBE_VALID_DIMENSIONS) == 1) break;
      }

      if ((header["valid"] & RGBE_VALID_FORMAT) == 0) {
        return rgbe_error(rgbe_format_error, 'missing format specifier');
      }

      if ((header["valid"] & RGBE_VALID_DIMENSIONS) == 0) {
        return rgbe_error(rgbe_format_error, 'missing image size specifier');
      }

      return header;
    };

    var RGBE_ReadPixels_RLE = (Uint8List buffer, int w, int h) {
      int scanline_width = w;

      if (
          // run length encoding is not allowed so read flat
          ((scanline_width < 8) || (scanline_width > 0x7fff)) ||
              // this file is not run length encoded
              ((2 != buffer[0]) ||
                  (2 != buffer[1]) ||
                  ((buffer[2] & 0x80) != 0))) {
        // return the flat buffer
        return buffer;
      }

      if (scanline_width != ((buffer[2] << 8) | buffer[3])) {
        return rgbe_error(rgbe_format_error, 'wrong scanline width');
      }

      var data_rgba = new Uint8List(4 * w * h);

      if (data_rgba.length == 0) {
        return rgbe_error(rgbe_memory_error, 'unable to allocate buffer space');
      }

      var offset = 0, pos = 0;

      var ptr_end = 4 * scanline_width;
      var rgbeStart = new Uint8List(4);
      var scanline_buffer = new Uint8List(ptr_end);
      var num_scanlines = h;

      // read in each successive scanline
      while ((num_scanlines > 0) && (pos < buffer.lengthInBytes)) {
        if (pos + 4 > buffer.lengthInBytes) {
          return rgbe_error(rgbe_read_error, null);
        }

        rgbeStart[0] = buffer[pos++];
        rgbeStart[1] = buffer[pos++];
        rgbeStart[2] = buffer[pos++];
        rgbeStart[3] = buffer[pos++];

        if ((2 != rgbeStart[0]) ||
            (2 != rgbeStart[1]) ||
            (((rgbeStart[2] << 8) | rgbeStart[3]) != scanline_width)) {
          return rgbe_error(rgbe_format_error, 'bad rgbe scanline format');
        }

        // read each of the four channels for the scanline into the buffer
        // first red, then green, then blue, then exponent
        var ptr = 0;
        int count;

        while ((ptr < ptr_end) && (pos < buffer.lengthInBytes)) {
          count = buffer[pos++];
          var isEncodedRun = count > 128;
          if (isEncodedRun) count -= 128;

          if ((0 == count) || (ptr + count > ptr_end)) {
            return rgbe_error(rgbe_format_error, 'bad scanline data');
          }

          if (isEncodedRun) {
            // a (encoded) run of the same value
            var byteValue = buffer[pos++];
            for (var i = 0; i < count; i++) {
              scanline_buffer[ptr++] = byteValue;
            }
            //ptr += count;

          } else {
            // a literal-run
            scanline_buffer.setAll(ptr, buffer.sublist(pos, pos + count));
            ptr += count;
            pos += count;
          }
        }

        // now convert data from buffer into rgba
        // first red, then green, then blue, then exponent (alpha)
        var l = scanline_width; //scanline_buffer.lengthInBytes;
        for (var i = 0; i < l; i++) {
          var off = 0;
          data_rgba[offset] = scanline_buffer[i + off];
          off += scanline_width; //1;
          data_rgba[offset + 1] = scanline_buffer[i + off];
          off += scanline_width; //1;
          data_rgba[offset + 2] = scanline_buffer[i + off];
          off += scanline_width; //1;
          data_rgba[offset + 3] = scanline_buffer[i + off];
          offset += 4;
        }

        num_scanlines--;
      }

      return data_rgba;
    };

    var RGBEByteToRGBFloat =
        (sourceArray, sourceOffset, destArray, destOffset) {
      var e = sourceArray[sourceOffset + 3];
      var scale = Math.pow(2.0, e - 128.0) / 255.0;

      destArray[destOffset + 0] = sourceArray[sourceOffset + 0] * scale;
      destArray[destOffset + 1] = sourceArray[sourceOffset + 1] * scale;
      destArray[destOffset + 2] = sourceArray[sourceOffset + 2] * scale;
      destArray[destOffset + 3] = 1;
    };

    var RGBEByteToRGBHalf = (sourceArray, sourceOffset, destArray, destOffset) {
      var e = sourceArray[sourceOffset + 3];
      var scale = Math.pow(2.0, e - 128.0) / 255.0;

      // clamping to 65504, the maximum representable value in float16
      destArray[destOffset + 0] = DataUtils.toHalfFloat(
          Math.min(sourceArray[sourceOffset + 0] * scale, 65504));
      destArray[destOffset + 1] = DataUtils.toHalfFloat(
          Math.min(sourceArray[sourceOffset + 1] * scale, 65504));
      destArray[destOffset + 2] = DataUtils.toHalfFloat(
          Math.min(sourceArray[sourceOffset + 2] * scale, 65504));
      destArray[destOffset + 3] = DataUtils.toHalfFloat(1.0);
    };

    // var byteArray = new Uint8Array( buffer );
    // byteArray.pos = 0;
    var byteArray = buffer;

    var rgbe_header_info = RGBE_ReadHeader(byteArray);

    if (RGBE_RETURN_FAILURE != rgbe_header_info) {
      rgbe_header_info = rgbe_header_info as Map<String, dynamic>;

      var w = rgbe_header_info["width"], h = rgbe_header_info["height"];

      Uint8List image_rgba_data =
          RGBE_ReadPixels_RLE(byteArray.sublist(byteArrayPos), w, h)
              as Uint8List;
      
      if (RGBE_RETURN_FAILURE != image_rgba_data) {
        var data, format, type;
        int numElements;

        switch (this.type) {

          // case UnsignedByteType:

          // 	data = image_rgba_data;
          // 	format = RGBEFormat; // handled as THREE.RGBAFormat in shaders
          // 	type = UnsignedByteType;
          // 	break;

          case FloatType:
            numElements = image_rgba_data.length ~/ 4;
            var floatArray = new Float32Array(numElements * 4);

            for (var j = 0; j < numElements; j++) {
              RGBEByteToRGBFloat(image_rgba_data, j * 4, floatArray, j * 4);
            }

            data = floatArray;
            type = FloatType;
            break;

          case HalfFloatType:
            numElements = image_rgba_data.length ~/ 4;
            var halfArray = new Uint16Array(numElements * 4);

            for (var j = 0; j < numElements; j++) {
              RGBEByteToRGBHalf(image_rgba_data, j * 4, halfArray, j * 4);
            }

            data = halfArray;
            type = HalfFloatType;
            break;

          default:
            print('THREE.RGBELoader: unsupported type: ${this.type}');
            break;
        }

        return {
          "width": w,
          "height": h,
          "data": data,
          "header": rgbe_header_info["string"],
          "gamma": rgbe_header_info["gamma"],
          "exposure": rgbe_header_info["exposure"],
          "format": format,
          "type": type
        };
      }
    }

    return null;
  }

  setDataType(value) {
    this.type = value;
    return this;
  }

  loadAsync(url) async {
    var completer = Completer();

    load(url, (result) {
      completer.complete(result);
    });

    return completer.future;
  }

  load(url, onLoad, [onProgress, onError]) {
    var onLoadCallback = (texture, texData) {
      switch (texture.type) {
        case UnsignedByteType:
          texture.encoding = RGBEEncoding;
          texture.minFilter = NearestFilter;
          texture.magFilter = NearestFilter;
          texture.generateMipmaps = false;
          texture.flipY = true;
          break;

        case FloatType:
          texture.encoding = LinearEncoding;
          texture.minFilter = LinearFilter;
          texture.magFilter = LinearFilter;
          texture.generateMipmaps = false;
          texture.flipY = true;
          break;

        case HalfFloatType:
          texture.encoding = LinearEncoding;
          texture.minFilter = LinearFilter;
          texture.magFilter = LinearFilter;
          texture.generateMipmaps = false;
          texture.flipY = true;
          break;
      }

      if (onLoad != null) onLoad(texture);
    };

    return super.load(url, onLoadCallback, onProgress, onError);
  }
}
