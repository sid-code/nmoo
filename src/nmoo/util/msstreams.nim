# polyfills for multisync streams

import streams
import asyncdispatch
import boost/io/asyncstreams

proc writeData*(s: Stream, data: string) =
  s.writeData(data.cstring, data.len)

proc write*[T](s: AsyncStream, x: T) {.async.} =
  when T is uint32:
    await s.writeUint32(x)
    return

  when T is int32:
    await s.writeInt32(x)
    return

  when T is uint64:
    await s.writeUint64(x)
    return

  when T is int64:
    await s.writeInt64(x)
    return

  when T is float64:
    await s.writeFloat64(x)
    return

  when T is uint8:
    await s.writeUint8(x)
    return

  assert false

proc readStr*(s: AsyncStream, length: int): Future[TaintedString] {.async.} =
  return await s.readData(length)

# Write a string by writing the length first then the string
proc writeStrl*(s: Stream | AsyncStream, str: string) {.multisync.} =
  await s.write(int32(str.len))
  await s.writeData(str)

# Reads an int32 then reads that many characters into a string
proc readStrl*(s: Stream | AsyncStream): Future[string] {.multisync.} =
  let slen = await s.readInt32()
  return await s.readStr(int(slen))
