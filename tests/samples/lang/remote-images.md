# Remote image policy

https (allowed):

![https](https://raw.githubusercontent.com/oxgenet/mdr/main/tests/samples/lang/test.png)

http to a private address (allowed, shows a failure placeholder if nothing answers):

![lan](http://192.168.255.254:8000/missing.png)

http to a public host (blocked by policy):

![public](http://example.com/blocked.png)
