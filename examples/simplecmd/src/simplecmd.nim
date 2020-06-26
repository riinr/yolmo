import yolmo, tables, streams, strutils

when isMainModule:
  let definition = staticReadDef(currentSourcePath.replace(".nim", ".yml"))
  let command = commandOf(definition)

  cli(command, call):
    if call.flags["help"]:
      echo definition
    else:
      for name, active in call.flags.pairs:
        if active:
          echo(name)
      for name, values in call.params.pairs:
        if values.len > 0:
          for value in values: 
            echo(name, ": ", value)
