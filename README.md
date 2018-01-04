# H2Swift

An implementation of the [HTTP/2 protocol](http://httpwg.org/specs/rfc7540.html) in pure Swift. Handles [HPACK](http://httpwg.org/specs/rfc7541.html) encoding/decoding, framing, transmission windows, and more.

The primary reason for this library's existence is to aid me in learning my way around the protocol, while providing me a place to implement some of the proposed extension specifications from the IETF, such as [WebSocket bootstrapping](https://datatracker.ietf.org/doc/draft-mcmanus-httpbis-h2-websockets/), [ORIGIN frames](https://datatracker.ietf.org/doc/draft-ietf-httpbis-origin-frame/), [structured headers](https://datatracker.ietf.org/doc/draft-ietf-httpbis-header-structure/), etc.
