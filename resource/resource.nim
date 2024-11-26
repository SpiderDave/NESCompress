{.used.}
when defined(vcc):
  {.link: "appVcc.res".}

elif defined(cpu64):
  when defined(tcc):
    {.link: "appTcc64.res".}

  else:
    {.link: "app64.res".}

else:
  when defined(tcc):
    {.link: "appTcc32.res".}

  else:
    {.link: "app32.res".}
