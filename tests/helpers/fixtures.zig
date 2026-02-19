/// Test fixtures - Canned CDP JSON responses

// ─── Browser.getVersion ─────────────────────────────────────
pub const browser_version_result =
    \\{"protocolVersion":"1.3","product":"Chrome/120.0.6099.109","revision":"@abc123","userAgent":"Mozilla/5.0","jsVersion":"12.0.267.8"}
;

// ─── Page.navigate ──────────────────────────────────────────
pub const page_navigate_result =
    \\{"frameId":"FRAME_001","loaderId":"LOADER_001"}
;

pub const page_navigate_error_result =
    \\{"frameId":"FRAME_001","loaderId":"LOADER_001","errorText":"net::ERR_NAME_NOT_RESOLVED"}
;

// ─── Page.captureScreenshot ─────────────────────────────────
pub const page_screenshot_result =
    \\{"data":"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="}
;

// ─── Runtime.evaluate ───────────────────────────────────────
pub const runtime_evaluate_number =
    \\{"result":{"type":"number","value":42,"description":"42"}}
;

pub const runtime_evaluate_string =
    \\{"result":{"type":"string","value":"hello world"}}
;

pub const runtime_evaluate_object =
    \\{"result":{"type":"object","className":"Object","description":"Object","objectId":"obj-123"}}
;

pub const runtime_evaluate_undefined =
    \\{"result":{"type":"undefined"}}
;

pub const runtime_evaluate_exception =
    \\{"exceptionDetails":{"exceptionId":1,"text":"Uncaught ReferenceError: foo is not defined","lineNumber":0,"columnNumber":0,"exception":{"type":"object","subtype":"error","className":"ReferenceError","description":"ReferenceError: foo is not defined"}}}
;

// ─── Target.getTargets ──────────────────────────────────────
pub const target_get_targets_result =
    \\{"targetInfos":[{"targetId":"TARGET_001","type":"page","title":"New Tab","url":"chrome://newtab/","attached":false,"browserContextId":"CTX_001"}]}
;

pub const target_attach_result =
    \\{"sessionId":"SESSION_001"}
;

pub const target_create_result =
    \\{"targetId":"TARGET_002"}
;

// ─── Network events ─────────────────────────────────────────
pub const network_request_will_be_sent =
    \\{"method":"Network.requestWillBeSent","params":{"requestId":"REQ_001","loaderId":"LOADER_001","documentURL":"https://example.com","request":{"url":"https://example.com","method":"GET","headers":{}},"timestamp":12345.678,"type":"Document"}}
;

pub const network_response_received =
    \\{"method":"Network.responseReceived","params":{"requestId":"REQ_001","response":{"url":"https://example.com","status":200,"statusText":"OK","headers":{"content-type":"text/html"},"mimeType":"text/html"},"timestamp":12345.789,"type":"Document"}}
;

// ─── DOM ────────────────────────────────────────────────────
pub const dom_get_document_result =
    \\{"root":{"nodeId":1,"nodeType":9,"nodeName":"#document","nodeValue":"","childNodeCount":2}}
;

pub const dom_query_selector_result =
    \\{"nodeId":42}
;

pub const dom_get_outer_html_result =
    \\{"outerHTML":"<h1>Example Domain</h1>"}
;

// ─── CDP errors ─────────────────────────────────────────────
pub const error_method_not_found =
    \\{"code":-32601,"message":"'Fake.nonexistent' wasn't found"}
;

pub const error_invalid_params =
    \\{"code":-32602,"message":"Invalid parameters: url is required"}
;

pub const error_target_crashed =
    \\{"code":-32000,"message":"Target crashed"}
;

// ─── Page events ────────────────────────────────────────────
pub const page_load_event_fired =
    \\{"method":"Page.loadEventFired","params":{"timestamp":12345.999}}
;

pub const page_frame_navigated =
    \\{"method":"Page.frameNavigated","params":{"frame":{"id":"FRAME_001","loaderId":"LOADER_001","url":"https://example.com","mimeType":"text/html","securityOrigin":"https://example.com"}}}
;

pub const page_dom_content_event_fired =
    \\{"method":"Page.domContentEventFired","params":{"timestamp":12345.888}}
;
