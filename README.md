# crystal-community

TODO: Write a description here

## Installation

TODO: Write installation instructions here

## Usage

TODO: Write usage instructions here

## Development

### Auto reload (sentry.cr)

This project uses [sentry.cr](https://github.com/samueleaton/sentry) for automatic rebuild/restart during development.

Installation (from project root directory):

```bash
curl -fsSLo- https://raw.githubusercontent.com/samueleaton/sentry/master/install.cr | crystal eval
```

Then run the `./sentry` command:

```bash
./sentry --install
```

The `.sentry.yml` file in this repo is configured to build `src/app.cr` and run the `./crystal-community` binary, watching `src/**/*.cr` and `src/**/*.ecr` files.

## Contributing

1. Fork it (<https://github.com/your-github-user/crystal-community/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Serdar Dogruyol](https://github.com/your-github-user) - creator and maintainer
