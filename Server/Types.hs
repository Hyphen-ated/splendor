{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TemplateHaskell #-}
module Server.Types where

import Control.Lens
import Data.Aeson
import Data.ByteString (ByteString)
import Data.Map (Map, mapKeys)
import qualified Data.Map as Map
import Data.Text (Text)
import Data.Traversable
import GHC.Generics
import Text.Read
import Splendor.Types

data PlayerInfo =
    PlayerInfo
        { _displayName :: Text
        }
    deriving (Eq, Show, Ord, Generic)

instance ToJSON PlayerInfo
instance FromJSON PlayerInfo

data RunningGame a =
    RunningGame
        { _players :: Map Int PlayerInfo
        , _version :: Int
        , _gameState :: a
        }
    deriving (Eq, Show, Ord, Functor, Generic)

instance ToJSON (Map Int PlayerInfo) where
    toJSON = toJSON . mapKeys show
    toEncoding = toEncoding . mapKeys show

instance FromJSON (Map Int PlayerInfo) where
    parseJSON val = do
        m <- parseJSON val
        assocList <- for (Map.toList m) $ \(k, v) -> do
            case readMaybe k of
                Nothing -> fail "Invalid color"
                Just c -> pure (c, v)
        pure (Map.fromList assocList)

instance ToJSON a => ToJSON (RunningGame a)
instance FromJSON a => FromJSON (RunningGame a)

data Instance
    = WaitingInstance
        { _waitingPlayers :: [(String, PlayerInfo)]
        , _ownerKey :: String
        }
    | RunningInstance
        { _playerKeys :: Map String Int
        , _runningGame :: RunningGame GameState
        }
    | CompletedInstance
        { _playerKeys :: Map String Int
        , _completedGame :: RunningGame GameState
        , _result :: GameResult
        }
    deriving (Eq, Show, Ord, Generic)

data InstanceView
    = WaitingInstanceView
        { _ivWaitingPlayers :: [PlayerInfo]
        }
    | RunningInstanceView
        { _ivRunningGame :: RunningGame GameView
        }
    | CompletedInstanceView
        { _ivCompletedGame :: RunningGame GameState
        , _ivResult :: GameResult
        }
    deriving (Eq, Show, Ord, Generic)

instance ToJSON InstanceView
instance FromJSON InstanceView

data InstanceState
    = Waiting
    | Running
    | Completed
    deriving (Eq, Show, Ord, Generic)

instance ToJSON InstanceState
instance FromJSON InstanceState

data InstanceSummary
    = InstanceSummary
        { _isPlayers :: [PlayerInfo]
        , _isState :: InstanceState
        }
    deriving (Eq, Show, Ord, Generic)

instance ToJSON InstanceSummary
instance FromJSON InstanceSummary

data ServerRequest a =
    ServerRequest
        { _playerKey :: String
        , _requestData :: a
        }
    deriving (Eq, Show, Ord, Generic)

instance ToJSON a => ToJSON (ServerRequest a)
instance FromJSON a => FromJSON (ServerRequest a)

data RequestData
    = ListLobbies
    | NewLobby PlayerInfo
    | JoinLobby String PlayerInfo
    | LeaveLobby String
    | StartGame String
    | GetGameState String
    | GameAction String Action
    deriving (Eq, Show, Ord, Generic)

instance ToJSON RequestData
instance FromJSON RequestData

data ServerResponse
    = ErrorResponse String
    | OkResponse Value
    deriving (Eq, Show, Generic)

instance ToJSON ServerResponse
instance FromJSON ServerResponse

data ServerState =
    ServerState
        { _instances :: Map String Instance
        }
    deriving (Eq, Show, Ord)

makeLenses ''PlayerInfo
makeLenses ''RunningGame
makeLenses ''Instance
makeLenses ''InstanceView
makeLenses ''ServerState
makeLenses ''ServerRequest
