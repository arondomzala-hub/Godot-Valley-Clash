extends RefCounted
## Web-only Colyseus room adapter.
##
## On Web exports the Colyseus GDExtension is unavailable, so this class talks
## to the Colyseus JS SDK (loaded in the page via the export preset's
## html/head_include, UMD global "Colyseus") through JavaScriptBridge.
##
## Mirrors the lifecycle surface of Colyseus.Room that network_manager.gd uses:
## signals joined / error / left, a `connected` property, and leave().

signal joined()
signal error(code: int, message: String)
signal left(code: int, reason: String)

var connected: bool = false

# JS glue object (window.__valleyNet) and persistent callback references.
# The JavaScriptObject callbacks MUST stay referenced as members, otherwise
# they get garbage-collected and the JS side calls into freed memory.
var _glue: JavaScriptObject
var _joined_cb: JavaScriptObject
var _error_cb: JavaScriptObject
var _left_cb: JavaScriptObject

const _GLUE_JS := """
(function () {
	if (window.__valleyNet) return;
	window.__valleyNet = {
		room: null,
		joinRoom: function (endpoint, roomName, optionsJson, asHost, onJoined, onError, onLeft) {
			var self = this;
			self.leaveRoom();
			if (typeof Colyseus === "undefined") {
				onError(0, "Colyseus JS SDK not loaded (check html/head_include).");
				return;
			}
			var options;
			try {
				options = JSON.parse(optionsJson);
			} catch (e) {
				options = {};
			}
			var client = new Colyseus.Client(endpoint);
			var promise = asHost
				? client.create(roomName, options)
				: client.join(roomName, options);
			promise.then(function (room) {
				self.room = room;
				room.onError(function (code, message) {
					onError(code || 0, message || "");
				});
				room.onLeave(function (code) {
					self.room = null;
					onLeft(code || 0, "");
				});
				onJoined();
			}).catch(function (e) {
				var code = (e && typeof e.code === "number") ? e.code : 0;
				var message = (e && e.message) ? e.message : String(e);
				onError(code, message);
			});
		},
		leaveRoom: function () {
			if (this.room) {
				try { this.room.leave(); } catch (e) {}
				this.room = null;
			}
		}
	};
})();
"""


func _init() -> void:
	if not OS.has_feature("web"):
		push_error("web_network.gd instantiated on a non-web platform.")
		return
	JavaScriptBridge.eval(_GLUE_JS, true)
	_glue = JavaScriptBridge.get_interface("__valleyNet")
	_joined_cb = JavaScriptBridge.create_callback(_on_js_joined)
	_error_cb = JavaScriptBridge.create_callback(_on_js_error)
	_left_cb = JavaScriptBridge.create_callback(_on_js_left)


## Create (host) or join a room. Mirrors Colyseus.Client.create/join.
func join_room(endpoint: String, room_name: String, options: Dictionary, as_host: bool) -> void:
	if _glue == null:
		error.emit(0, "Web network glue unavailable.")
		return
	_glue.joinRoom(endpoint, room_name, JSON.stringify(options), as_host,
			_joined_cb, _error_cb, _left_cb)


func leave() -> void:
	connected = false
	if _glue != null:
		_glue.leaveRoom()


func _on_js_joined(_args: Array) -> void:
	connected = true
	joined.emit()


func _on_js_error(args: Array) -> void:
	connected = false
	var code: int = int(args[0]) if args.size() > 0 and args[0] != null else 0
	var message: String = str(args[1]) if args.size() > 1 and args[1] != null else ""
	error.emit(code, message)


func _on_js_left(args: Array) -> void:
	connected = false
	var code: int = int(args[0]) if args.size() > 0 and args[0] != null else 0
	var reason: String = str(args[1]) if args.size() > 1 and args[1] != null else ""
	left.emit(code, reason)
