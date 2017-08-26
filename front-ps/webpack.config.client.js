
const spawn = require('child_process').spawn
const path = require('path')
const webpack = require('webpack')

const NamedModulesPlugin = require('webpack/lib/NamedModulesPlugin');

const isProd = process.env.NODE_ENV === 'production'

const plugins = [
  new webpack.ProgressPlugin(),
  new webpack.DefinePlugin({
    'process.env.NODE_ENV': JSON.stringify(process.env.NODE_ENV),
    '$PRODUCTION': isProd
  }),
  new NamedModulesPlugin(),
]

if (isProd) {
  plugins.push(
    new webpack.LoaderOptionsPlugin({
      minimize: true,
      debug: false
    }),
    new webpack.HashedModuleIdsPlugin({
      hashFunction: 'sha256',
      hashDigest: 'hex',
      hashDigestLength: 20
    })
  )
} else {
  plugins.push(
    new webpack.HotModuleReplacementPlugin(),
    new webpack.NoEmitOnErrorsPlugin()
  )
}

const config = {
  entry: {
    "category-overview": path.join(__dirname, 'client', 'Guide', 'Client', 'CategoryOverview-entry.js'),
    "category-detail": path.join(__dirname, 'client', 'Guide', 'Client', 'CategoryDetail-entry.js'),
  },
  output: {
    path: path.join(__dirname, '/public'),
    publicPath: '/',
    filename: '[name].js',
    pathinfo: true
  },
  plugins: plugins,
  module: {
    loaders: [
      {
        test: /\.purs$/,
        loader: 'purs-loader',
        exclude: /node_modules/,
        query: {
          psc: 'psa',
          src: [
            path.join(__dirname, 'common', '**', '*.purs'),
            path.join(__dirname, 'client', '**', '*.purs'),
            path.join(__dirname, 'bower_components', 'purescript-*', 'src', '**', '*.purs')
          ],
          bundle: isProd
        }
      }
    ],
  },
  resolveLoader: {
    modules: [
      path.join(__dirname, 'node_modules')
    ]
  },
  resolve: {
    extensions: [ '.js', '.purs'],
    alias: {
      'react': 'preact-compat',
      'react-dom': 'preact-compat',
      'create-react-class': 'preact-compat/lib/create-react-class'
    },
    modules: [
      'node_modules',
      'bower_components'
    ],
    extensions: ['.js', '.purs']
  },
  performance: { hints: false },
  stats: {
    hash: false,
    timings: false,
    version: false,
    assets: false,
    errors: true,
    colors: false,
    chunks: false,
    children: false,
    cached: false,
    modules: false,
    chunkModules: false
  }
}
module.exports = config
