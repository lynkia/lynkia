# Lynkia

## Installation

Step 1: Install erlang

Step 2: Clone the repository

```
git clone https://github.com/lynkia/lynkia.git
```

## Getting started

### Shell

Step 1: Start the nodes.

Open two different terminals.

On the first one, type:

`rebar3 shell --name lynkia1@127.0.0.1 --apps lynkia`

On the second one, type:

`rebar3 shell --name lynkia2@127.0.0.1 --apps lynkia`

Step 2: Link the nodes

You can either:

- Enter `lynkia_utils:join('lynkia1@127.0.0.1').` on `lynkia2`
- Enter `lynkia_utils:join('lynkia2@127.0.0.1').` on `lynkia1`

Step 3: Verify that your two nodes are connected

`lynkia_utils:members().`

## Generate the documentation

```
rebar3 edoc
```