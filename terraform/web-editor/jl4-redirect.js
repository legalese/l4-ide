// Viewer-request function for the old editor hostname: sends every request to
// the same path and query on ${domain}, so shared ?id= and ?program= links
// keep working. Query values are passed through as they arrived.
function handler(event) {
  var request = event.request;
  var pairs = [];
  for (var name in request.querystring) {
    var param = request.querystring[name];
    var values = param.multiValue ? param.multiValue : [param];
    for (var i = 0; i < values.length; i++) {
      pairs.push(values[i].value === "" ? name : name + "=" + values[i].value);
    }
  }
  var query = pairs.length > 0 ? "?" + pairs.join("&") : "";

  return {
    statusCode: 301,
    statusDescription: "Moved Permanently",
    headers: {
      location: { value: "https://${domain}" + request.uri + query },
      "cache-control": { value: "public, max-age=86400" },
    },
  };
}
