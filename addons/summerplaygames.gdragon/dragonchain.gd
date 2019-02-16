extends Node

class_name DragonChain

export var dragonchain_id : String
export var auth_key : String
export var auth_key_id : String
var endpoint : String = "api.dragonchain.com"
var port : int = 80
var use_ssl : bool = true
var verify : bool = true

var _verb_map : Dictionary = {
	"GET": HTTPClient.METHOD_GET,
	"POST": HTTPClient.METHOD_POST,
	"PUT": HTTPClient.METHOD_PUT,
	"DELETE": HTTPClient.METHOD_DELETE,
}

onready var _http : HTTPClient = HTTPClient.new()

func _ready():
	var host := self.dragonchain_id + "." + endpoint
	var err := _http.connect_to_host(host, port, use_ssl, verify)
	assert(err == OK)
	print("Connecting to DragonChain at %s..." % host)
	while _http.get_status() == HTTPClient.STATUS_CONNECTING or _http.get_status() == HTTPClient.STATUS_RESOLVING:
		_http.poll()
		OS.delay_msec(500)
	
	assert(_http.get_status() == HTTPClient.STATUS_CONNECTED)
	print("Connected to DragonChain.")

func get_status() -> Dictionary:
	return _make_request("GET", "/path")

func query_contracts(query : String="", sort : String="", offset : int = 0, limit : int = 10) -> Dictionary:
	var query_params := _get_lucene_query_params(query, sort, offset, limit)
	return _make_request("GET", "/contract", query)

func get_contract(name : String) -> Dictionary:
	return _make_request("GET", "/contract/"+name)

func post_library_contract(contract : LibraryContract) -> Dictionary:
	# TODO: Validate library
	var body := {
		"version": "2",
		"origin": "library",
		"name": contract.name,
		"libraryContractName": contract.library,
	}
	if contract.env_vars:
		body["custom_environment_variables"] = contract.env_vars
	return _make_request("POST", "/contract/"+name, JSON.print(body))

func post_custom_contract(contract : CustomContract) -> Dictionary:
	# TODO: Validate runtime and sc_type
	var body := {
		"version": "2",
		"origin": "custom",
		"name": contract.name,
		"code": contract.code,
		"runtime": contract.runtime,
		"sc_type": contract.sc_type,
		"is_serial": contract.serial,
		"handler": contract.handler,
	}
	if contract.env_vars:
		body["custom_environment_variables"] = contract.env_vars
	return _make_request("POST", "/contract/" + contract.name, JSON.print(body))

func query_transactions(query : String = "", sort : String = "", offset : int = 0, limit : int = 10) -> Dictionary:
	var query_params := _get_lucene_query_params(query, sort, offset, limit)
	return _make_request("GET", "/transaction", query_params)

func get_transaction(txn_id : String) -> Dictionary:
	return _make_request("GET", "/transaction/"+txn_id)

func post_transaction(txn_type : String, payload : Dictionary, tag : String = "") -> Dictionary:
	var body := {
		"version": "1",
		"txn_type": txn_type,
		"payload": payload,
	}
	if tag:
		body["tag"] = tag
	return _make_request("POST", "/transaction", JSON.print(body))

func post_transaction_string(txn_type : String, payload : String, tag : String = "") -> Dictionary:
	return post_transaction(txn_type, parse_json(payload), tag)

func post_transaction_bulk(txns : Array) -> Dictionary:
	var post_data := []
	for txn in txns:
		var body := {
			"version": "1",
			"txn_type": txn.get("txn_type"),
			"payload": payload.get("payload"),
		}
		if txn.has("payload"):
			body["tag"] = txn.get("tag")
		post_data.append(body)
	return _make_request("POST", "/transaction_bulk", JSON.print(post_data))

func _make_request(http_verb : String, path : String, body : String = "") -> Dictionary:
	print("creating request ", http_verb, path)
	http_verb = http_verb.to_upper()
	var content_type := "application/json"
	var ts := _get_timestamp()
	var auth := _get_auth(http_verb, path, ts, body, content_type)
	var headers := _get_headers(ts, auth, content_type)
	var err := _http.request(_verb_map[http_verb], path, headers, body)
	assert(err == OK)
	while _http.get_status() == HTTPClient.STATUS_REQUESTING:
		_http.poll()
		if not OS.has_feature("web"):
			OS.delay_msec(500)
		else:
			# Synchronous HTTP requests are not supposed on the web,
			# so wait for the next main loop iteration.
			yield(Engine.get_main_loop(), "idle_frame")
	assert(_http.get_status() == HTTPClient.STATUS_BODY or _http.get_status() == HTTPClient.STATUS_CONNECTED)
	if _http.has_response():
		var resp_buf := PoolByteArray()
		while _http.get_status() == HTTPClient.STATUS_BODY:
			_http.poll()
			var chunk := _http.read_response_body_chunk()
			if chunk.size() == 0:
				OS.delay_msec(1000)
			else:
				resp_buf += chunk
		return parse_json(resp_buf.get_string_from_utf8())
	return null

func _get_timestamp() -> String:
	return ""

func _get_auth(http_verb : String, path : String, ts : String, content : String, content_type : String = "") -> String:
	var hashedb64 := Marshalls.utf8_to_base64(content.sha256_text())
	var msg_string := "%s\n%s\n%s\n%s\n%s\n%s".format([http_verb.to_upper(), path, self.dragonchain_id, ts, content_type, hashedb64], "%s")
	var hmac := _get_hmac(msg_string)
	return "DC1-HMAC-SHA256 %s:%s" % [self.auth_key_id, hmac]

func _get_hmac(message_string : String) -> PoolByteArray:
	return PoolByteArray()

func _get_headers(ts : String, auth : String, content_type : String = "") -> PoolStringArray:
	var headers := [
		"dragonchain: " + self.dragonchain_id,
		"timestamp: ", ts,
		"Authorization: ", auth
	]
	if content_type:
		headers.append("Content-Type: " + content_type)
	return PoolStringArray(headers)

func _get_lucene_query_params(query : String, sort : String, offset : int, limit : int) -> String:
	var params := {
		"offset": offset,
		"limit": limit,
	}
	if query:
		params["q"] = query
	if sort:
		params["sort"] = sort
	return _http.query_string_from_dict(params)

func _is_library_contract_valid(contract : String) -> bool:
	return contract in [
		"currency",
		"interchainWatcher",
		"neoWatcher",
		"btcWatcher",
		"ethereumPublisher",
		"neoPublisher",
		"btcPublisher",
	]
	
	




	


	

