import yaml.serialization, streams, options, parseopt,
  sequtils, strutils, tables, macros
from strformat import fmt

func ie(short: Option[char]): string =
  short.map(func (s: char): string = fmt "-{s}|").get("")

func ie[T](values: seq[T]): string =
  values.map(func (v: T): string = fmt "{v.ie}").join(" ")

type
  ParsedOpt = tuple
    kind: CmdLineKind
    key: TaintedString
    value: string

type
  Param* = object
    name*: string
    required*: bool
    short*: Option[char]
    `type`*: Option[string]
    default*: Option[string]
    example*: Option[string]
    description*: Option[string]

setDefaultValue(Param, short, none(char))
setDefaultValue(Param, example, none(string))
setDefaultValue(Param, description, none(string))
setDefaultValue(Param, type, none(string))
setDefaultValue(Param, required, false)
setDefaultValue(Param, default, none(string))

proc `$`(param: Param): string = dump(param)

func ie(param: Param): string =
  let defaultValue = param.default.get("paramValue")
  fmt "[{param.short.ie}--{param.name}={defaultValue}]"

func `==`(param: Param, opt: ParsedOpt): bool =
  opt.value.len > 0 and (
    opt.kind == CmdLineKind.cmdLongOption and
    opt.key == param.name
  ) or (
    opt.kind == CmdLineKind.cmdShortOption and
    opt.key[0] == param.short.get('-')
  )

type
  Flag* = object
    name*: string
    short*: Option[char]
    example*: Option[string]
    description*: Option[string]

setDefaultValue(Flag, short, none(char))
setDefaultValue(Flag, example, none(string))
setDefaultValue(Flag, description, none(string))
 
proc `$`(flag: Flag): string = dump(flag)

func ie(flag: Flag): string =
  fmt "[{flag.short.ie}--{flag.name}]"

func `==`(flag: Flag, opt: ParsedOpt): bool =
  opt.value.len == 0 and (
    opt.kind == CmdLineKind.cmdLongOption and
    opt.key == flag.name
  ) or (
    opt.kind == CmdLineKind.cmdShortOption and
    opt.key[0] == flag.short.get('-')
  )

type
  Command* = object
    name*: string
    short*: Option[char]
    example*: Option[string]
    description*: Option[string]
    version*: Option[string]
    flags*: seq[Flag]
    params*: seq[Param]

setDefaultValue(Command, short, none(char))
setDefaultValue(Command, example, none(string))
setDefaultValue(Command, description, none(string))
setDefaultValue(Command, version, some("0.0.0"))
setDefaultValue(Command, flags, @[])
setDefaultValue(Command, params, @[])

proc `$`(command: Command): string = dump(command)

func ie(command: Command): string =
  fmt "{command.name} {command.flags.ie} {command.params.ie} arg0 ... argN"

func help(command: Command): string =
  fmt """
{command.name} version: {command.version.get("")}
{command.description.get("")}

usage:
{command.ie}

examples:
{command.example.get("")}"""

proc commandOf*(definition: Stream): Command = 
  var command: Command
  load(definition, command)
  definition.close()
  return command

proc commandOf*(definition: string): Command =
  commandOf(newStringStream(definition))

macro staticReadDef*(file: static[string]): untyped =
  let
    expString = newLit(slurp(file))
  result = quote do:
    `expString`

proc staticCommandOf*(file: static[string]): Command =
  commandOf(staticReadDef(file))

type Call = object
  command: Command
  flags: ref Table[string, bool]
  params: ref Table[string, seq[TaintedString]]
  args: seq[TaintedString]
  all: seq[ParsedOpt]

proc newCallTable(flags: seq[Flag]): TableRef[string, bool] =
  newTable(
    flags.map(
      func(flag: Flag): (string, bool) =
        (flag.name, false)
    )
  )

proc newCallTable(params: seq[Param]): TableRef[string, seq[TaintedString]] =
  newTable(
    params.map(
      func(param: Param): (string, seq[TaintedString]) =
        (param.name, @[])
    )
  )

func nameOf(it: Flag): string = it.name

func names(flags: seq[Flag]): seq[string] = flags.map(nameOf)

func shortOf(it: Flag): Option[char] = it.short

func shorts(flags: seq[Flag]): seq[Option[char]] = flags.map(shortOf)

func toSet(c: Option[char]): set[char] =
  if c.isSome: { c.get }
  else: ({})

func toSet(items: seq[Option[char]]): set[char] =
  foldr(items.map(toSet), a + b)

proc commandCall*(command: Command): ref Call =
  var
    callInfo: ref Call
  new(callInfo)
  callInfo.args = @[]
  callInfo.all = @[] 
  callInfo.command = command
  callInfo.flags = newCallTable(command.flags)
  callInfo.params = newCallTable(command.params)

  let
    longNoVal = command.flags.names
    shortNoVal = command.flags.shorts.toSet 

  for (kind, key, value) in getopt(shortNoVal = shortNoVal, longNoVal = longNoVal):
    let opt: ParsedOpt = (kind, key, value)
    callInfo.all.insert(opt)
    let flags = command.flags.filter(proc (it: Flag): bool = it == opt)
    for it in flags:
      callInfo.flags[it.name] = true

    let params = command.params.filter(proc (it: Param): bool = it == opt)
    for it in params:
      callInfo.params[it.name] = concat(callInfo.params[it.name], @[value])

    if kind == CmdLineKind.cmdArgument:
      callInfo.args = concat(callInfo.args, @[key])
  return callInfo

template cli*(command: Command, callInfo: untyped, body: untyped): untyped =
  var callInfo: ref Call
  callInfo = commandCall(command)
  block:
    body

