import { Chain } from "viem";
import {
  arbitrum,
  arbitrumSepolia,
  avalanche,
  base,
  basecampTestnet,
  baseSepolia,
  berachain,
  berachainBepolia,
  blast,
  blastSepolia,
  bsc,
  ethernity,
  flowMainnet,
  flowTestnet,
  gnosis,
  gnosisChiado,
  ink,
  inkSepolia,
  lisk,
  liskSepolia,
  lumiaMainnet,
  mainnet,
  megaethTestnet,
  mode,
  monadTestnet,
  optimism,
  optimismSepolia,
  polygon,
  polygonAmoy,
  polygonZkEvm,
  sepolia,
  sonic,
  storyAeneid,
  unichain,
  unichainSepolia,
  zircuit,
  zora,
} from "viem/chains";

const thriveTestnet: Chain = {
  id: 1991,
  name: "Thrive Testnet",
  nativeCurrency: {
    decimals: 18,
    name: "Ether",
    symbol: "ETH",
  },
  rpcUrls: {
    default: {
      http: ["https://rpc.thrive-testnet.t.raas.gelato.cloud"],
    },
  },
  blockExplorers: {
    default: {
      name: "Thrive Testnet Explorer",
      url: "https://thrive-testnet.cloud.blockscout.com",
    },
  },
  testnet: true,
};

const abcTestnet: Chain = {
  id: 112112,
  name: "ABC Testnet",
  nativeCurrency: {
    decimals: 18,
    name: "Ether",
    symbol: "ETH",
  },
  rpcUrls: {
    default: {
      http: ["https://rpc.abc.t.raas.gelato.cloud"],
    },
  },
  blockExplorers: {
    default: {
      name: "ABC Testnet Explorer",
      url: "https://explorer.abc.t.raas.gelato.cloud",
    },
  },
  testnet: true,
};

const botanixTestnet: Chain = {
  id: 3636,
  name: 'Botanix Testnet',
  nativeCurrency: {
    name: 'Botanix',
    symbol: 'BTC',
    decimals: 18
  },
  rpcUrls: {
    default: {
      http: ['https://rpc.ankr.com/botanix_testnet'],
    },
  },
  blockExplorers: {
    default: {
      name: 'Botanix Testnet Explorer',
      url: 'https://testnet.botanixscan.io',
    },
  },
  testnet: true,
};

export const TESTNETS: Chain[] = [
  flowTestnet,
  unichainSepolia,
  storyAeneid,
  thriveTestnet,
  botanixTestnet,
  monadTestnet,
  liskSepolia,
  megaethTestnet,
  gnosisChiado,
  polygonAmoy,
  berachainBepolia,
  baseSepolia,
  arbitrumSepolia,
  inkSepolia,
  sepolia,
  optimismSepolia,
  blastSepolia,
  basecampTestnet,
  abcTestnet,
];

export const MAINNETS: Chain[] = [
  mainnet,
  optimism,
  bsc,
  gnosis,
  unichain,
  polygon,
  sonic,
  ethernity,
  flowMainnet,
  polygonZkEvm,
  lisk,
  base,
  mode,
  arbitrum,
  avalanche,
  zircuit,
  ink,
  berachain,
  blast,
  zora,
  lumiaMainnet,
];
