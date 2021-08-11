# ThingSim

ThingSim is CLI application that simulates IP based smarthome devices. It is
primarily intended for use in development of SmartThings device integrations.

# Status

Early

Base functionality exists. It is able to simulate one or more on/off "bulb"
devices with a line-oriented JSON-based RPC server.

It will probably be somewhat unreliable and there are very few guardrails in
place to prevent using it wrong which could lead to somewhat incomprehensible
errors.

# Use

ThingSim uses a command line interface for management of things.

Things can be added:

```
$ thingsim add bulb --protocols rpc --name "My Imaginary Bulb #1"
$ thingsim add bulb --protocols rpc --name "My Imaginary Bulb #2"
```

Things can be listed:

```
$ thingsim show
2 devices
2 are of type 'bulb'
 * foo (647afc6c-abb0-4ca8-2331-e1c5b4d4f262)
 * foo2 (592d3dc8-ba53-4fdb-2285-933f58e93225)
```

Things can be removed:

```
thing rm 592d3dc8-ba53-4fdb-2285-933f58e93225
```

And the simulator can be run:

```
thingsim run
```

For more run:

```
thingsim [command] --help
```
