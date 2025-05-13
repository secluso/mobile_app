import 'package:flutter/material.dart';

class LivestreamPage extends StatefulWidget {
  final String cameraName;

  LivestreamPage({required this.cameraName});

  @override
  _LivestreamPageState createState() => _LivestreamPageState();
}

class _LivestreamPageState extends State<LivestreamPage> {
  bool isStreaming = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Livestream - ${widget.cameraName}"),
        backgroundColor: const Color.fromARGB(255, 27, 114, 60),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Container(
                width: double.infinity,
                height: 300,
                color: Colors.black,
                alignment: Alignment.center,
                child:
                    isStreaming
                        ? Text(
                          "Live Stream Here",
                          style: TextStyle(color: Colors.white, fontSize: 18),
                        )
                        : Text(
                          "Stream Stopped",
                          style: TextStyle(color: Colors.red, fontSize: 18),
                        ),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                isStreaming = false;
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text("Stop Livestream"),
          ),
        ],
      ),
    );
  }
}
