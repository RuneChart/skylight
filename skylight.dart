// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Use the client program, number_guesser.dart to automatically make guesses.
// Or, you can manually guess the number using the URL localhost:4045/?q=#,
// where # is your guess.
// Or, you can use the make_a_guess.html UI.

// #docregion main
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:filesize/filesize.dart';

import 'package:http/http.dart' as http;

import 'package:http_parser/http_parser.dart';

import 'package:args/args.dart';

var portal = "https://siasky.net";

Future main(List<String> arguments) async {
  if (arguments.length != 2)
  {
    print("Format: skylight <port> <webportal url>");
    return;
  }
  
  var portNum = int.parse(arguments[0]);

  HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    portNum,
  );
  await for (var request in server) {
    handleRequest(request);
  }
}
// #enddocregion main

// #docregion handleRequest
void handleRequest(HttpRequest request) {
  try {
    // #docregion request-method
    if (request.method == 'GET') {
      handleGet(request);
    } else {
      // #enddocregion handleRequest
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..write('Unsupported request: ${request.method}.')
        ..close();
      // #docregion handleRequest
    }
    // #enddocregion request-method
  } catch (e) {
    print('Exception in handleRequest: $e');
  }
  print('Request handled.');
}
// #enddocregion handleRequest

// #docregion handleGet, statusCode, uri, write
void handleGet(HttpRequest request) {
  // #enddocregion write
  final hash = request.uri.queryParameters['h'];
  // #enddocregion uri
  final response = request.response;
  response.statusCode = HttpStatus.ok;
  // #enddocregion statusCode
  // #docregion write

    print('Downloading file index...');

    final lengthSep = hash.indexOf('-');

    final version = hash.substring(0, lengthSep);
    if (version == 'a') {
      response.write("Not supported");
      response.close();
    }

    print (hash);

    final sep = hash.indexOf('+');

    final skylink = hash.substring(hash.indexOf("-")+1, sep);
    final key = hash.substring(sep + 1);


    downloadAndDecrypt(
      skylink,
      key,
      response
    );
   
   //response
   //   ..writeln('So far so good')
   //   ..close();
    // #docregion write
  }
  // #docregion statusCode, uri

void downloadAndDecrypt(
  String skylink,
  String key,
  final response
) async {
  print(skylink);
  print(key);

  final res = await http.get('$portal/$skylink');

  final cryptParts = base64.decode(key);

  final cipher = CipherWithAppendedMac(aesCtr, Hmac(sha256));

  final secretKey = SecretKey(cryptParts.sublist(0, 32));

  final nonce = Nonce(cryptParts.sublist(32, 32 + 16));

  print('Decrypting file index...');

  final decryptedChunkIndex = await cipher.decrypt(
    res.bodyBytes,
    secretKey: secretKey,
    nonce: nonce,
  );

  final Map chunkIndex = json.decode(utf8.decode(decryptedChunkIndex));

  print(chunkIndex);

  final Map metadata = chunkIndex['metadata'];

  List<Uint8List> chunks = [];

  int i = 0;

  final int totalChunks = metadata['totalchunks'];

  final size = filesize(metadata['filesize']);

  final info = '${metadata["filename"]} ($size) •';

  print('$info Downloading and decrypting chunk 1 of $totalChunks...');

  int iDone = 0;

  for (final chunkSkylink in chunkIndex['chunks']) {
    final currentI = i;

    print('dl $currentI');

    final chunkNonce = Nonce(
        base64.decode(chunkIndex['chunkNonces'][(currentI + 1).toString()]));

    http
        .get(
      '$portal/$chunkSkylink',
    )
        .then((chunkRes) async {
      print('dcrypt $currentI');

      final decryptedChunk = await cipher.decrypt(
        chunkRes.bodyBytes,
        secretKey: secretKey,
        nonce: chunkNonce,
      );

      while (chunks.length < currentI) {
        await Future.delayed(Duration(milliseconds: 20));
      }
      print('done $currentI');

      chunks.add(decryptedChunk);

      if (currentI == totalChunks - 1) {
        for (Uint8List thisChunk in chunks){
          for (int thisByte in thisChunk)  {
            print(thisByte);
          }
          response.add(thisChunk);
        }
       
        await response.close();
        return;

      } else {
        print(
            '$info Downloading and decrypting chunk ${currentI + 2} of $totalChunks...');
      }
      iDone++;
    });

    await Future.delayed(Duration(milliseconds: 100));

    while (i > iDone + 4) {
      await Future.delayed(Duration(milliseconds: 20));
    }

    i++;
  }
}


