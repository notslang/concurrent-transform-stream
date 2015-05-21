# Concurrent Transform Stream
This is a modified version of the standard transform stream, made to execute transformations concurrently. It is useful if you are doing transformations on a stream that are not only asynchronous, but can be run in parallel (like network requests or calls to a sub-process).
