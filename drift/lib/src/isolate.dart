import 'dart:isolate';

import 'package:async/async.dart';
import 'package:meta/meta.dart';
import 'package:stream_channel/isolate_channel.dart';

import '../drift.dart';
import '../remote.dart';

// All of this is drift-internal and not exported, so:
// ignore_for_file: public_member_api_docs

@internal
class RunningDriftServer {
  final Isolate self;
  final bool killIsolateWhenDone;

  final DriftServer server;
  final ReceivePort connectPort = ReceivePort('drift connect');
  int _counter = 0;

  SendPort get portToOpenConnection => connectPort.sendPort;

  RunningDriftServer(this.self, DatabaseConnection connection,
      {this.killIsolateWhenDone = true})
      : server = DriftServer(connection, allowRemoteShutdown: true) {
    final subscription = connectPort.listen((message) {
      if (message is SendPort) {
        final receiveForConnection =
            ReceivePort('drift channel #${_counter++}');
        message.send(receiveForConnection.sendPort);
        final channel = IsolateChannel(receiveForConnection, message)
            .changeStream((source) => source.map(decodeAfterTransport))
            .transformSink(
              StreamSinkTransformer.fromHandlers(
                  handleData: (data, sink) =>
                      sink.add(prepareForTransport(data))),
            );

        server.serve(channel);
      }
    });

    server.done.then((_) {
      subscription.cancel();
      connectPort.close();
      if (killIsolateWhenDone) self.kill();
    });
  }
}

Object? prepareForTransport(Object? source) {
  if (source is! List) return source;

  if (source is Uint8List) {
    return TransferableTypedData.fromList([source]);
  }

  return source.map(prepareForTransport).toList();
}

Object? decodeAfterTransport(Object? source) {
  if (source is TransferableTypedData) {
    return source.materialize().asUint8List();
  } else if (source is List) {
    return source.map(decodeAfterTransport).toList();
  } else {
    return source;
  }
}
