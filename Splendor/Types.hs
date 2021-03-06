{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
module Splendor.Types where

import Control.Lens
import Data.Aeson
import Data.Map (Map, mapKeys)
import qualified Data.Map as Map
import Data.Traversable
import Data.Vector (Vector)
import qualified Data.Vector as V
import Text.Read
import GHC.Generics

newtype CardId = CardId Int
    deriving (Eq, Show, Ord, Enum, Generic)

instance ToJSON CardId
instance FromJSON CardId

newtype NobleId = NobleId Int
    deriving (Eq, Show, Ord, Enum, Generic)

instance ToJSON NobleId
instance FromJSON NobleId

data Color
    = Red
    | Green
    | Blue
    | White
    | Black
    deriving (Eq, Show, Read, Ord, Enum, Bounded, Generic)

instance ToJSON Color
instance FromJSON Color

instance ToJSON v => ToJSON (Map Color v) where
    toJSON = toJSON . mapKeys show
    toEncoding = toEncoding . mapKeys show

instance FromJSON v => FromJSON (Map Color v) where
    parseJSON val = do
        m <- parseJSON val
        assocList <- for (Map.toList m) $ \(k, v) -> do
            case readMaybe k of
                Nothing -> fail "Invalid color"
                Just c -> pure (c, v)
        pure (Map.fromList assocList)

data ChipType
    = Basic Color
    | Gold
    deriving (Eq, Show, Read, Ord, Generic)

instance ToJSON ChipType
instance FromJSON ChipType

instance ToJSON v => ToJSON (Map ChipType v) where
    toJSON = toJSON . mapKeys show
    toEncoding = toEncoding . mapKeys show

instance FromJSON v => FromJSON (Map ChipType v) where
    parseJSON val = do
        m <- parseJSON val
        assocList <- for (Map.toList m) $ \(k, v) -> do
            case readMaybe k of
                Nothing -> fail "Invalid color"
                Just c -> pure (c, v)
        pure (Map.fromList assocList)

data Action
    = Take3 (Maybe Color) (Maybe Color) (Maybe Color)
    | Take2 Color
    | Reserve CardId
    | ReserveTop Int
    | Buy CardId
    | Discard (Map ChipType Int)
    | SelectNoble NobleId
    deriving (Eq, Show, Ord, Generic)

instance ToJSON Action
instance FromJSON Action

data ActionSummary
    = Took3 [Color]
    | Took2 Color
    | Reserved Card
    | ReservedTop Int
    | Bought Card
    | Discarded (Map ChipType Int)
    | GainedNoble Noble
    deriving (Eq, Show, Ord, Generic)

instance ToJSON ActionSummary
instance FromJSON ActionSummary

data Card
    = Card
        { _cardId :: CardId
        , _cardColor :: Color
        , _cardPoints :: Int
        , _cardCost :: Map Color Int
        }
    deriving (Eq, Show, Ord, Generic)

instance ToJSON Card
instance FromJSON Card

data Noble
    = Noble
        { _nobleId :: NobleId
        , _nobleRequirement :: Map Color Int
        , _noblePoints :: Int
        }
    deriving (Eq, Show, Ord, Generic)

instance ToJSON Noble
instance FromJSON Noble

data PlayerState
    = PlayerState
        { _heldChips :: Map ChipType Int
        , _ownedCards :: [Card]
        , _ownedCardCounts :: Map Color Int
        , _reservedCards :: [Card]
        , _ownedNobles :: [Noble]
        , _currentVP :: Int
        }
    deriving (Eq, Show, Ord, Generic)

instance ToJSON PlayerState
instance FromJSON PlayerState

data PlayerView
    = PlayerView
        { _pvHeldChips :: Map ChipType Int
        , _pvOwnedCards :: [Card]
        , _pvOwnedCardCounts :: Map Color Int
        , _pvReservedCardCount :: Int
        , _pvOwnedNobles :: [Noble]
        , _pvCurrentVP :: Int
        }
    deriving (Eq, Show, Ord, Generic)

instance ToJSON PlayerView
instance FromJSON PlayerView

data TierState
    = TierState
        { _availableCards :: [Card]
        , _tierDeck :: [Card]
        }
    deriving (Eq, Show, Ord, Generic)

instance ToJSON TierState
instance FromJSON TierState

data TierView
    = TierView
        { _tvAvailableCards :: [Card]
        , _tvDeckCount :: Int
        }
    deriving (Eq, Show, Ord, Generic)

instance ToJSON TierView
instance FromJSON TierView

data ActionRequestType
    = TurnRequest
    | DiscardChipRequest Int
    | SelectNobleRequest
    deriving (Eq, Show, Ord, Generic)

instance ToJSON ActionRequestType
instance FromJSON ActionRequestType

data ActionRequest
    = ActionRequest
        { _requestPlayer :: Int
        , _requestType :: ActionRequestType
        }
    deriving (Eq, Show, Ord, Generic)

instance ToJSON ActionRequest
instance FromJSON ActionRequest

data GameState
    = GameState
        { _numPlayers :: Int
        , _playerStates :: Vector PlayerState
        , _availableChips :: Map ChipType Int
        , _availableNobles :: [Noble]
        , _tier1State :: TierState
        , _tier2State :: TierState
        , _tier3State :: TierState
        , _currentRequest :: ActionRequest
        , _actionLog :: [(Int, ActionSummary)]
        }
    deriving (Eq, Show, Ord, Generic)

instance ToJSON GameState
instance FromJSON GameState

data GameResult
    = GameWinners [Int]
    deriving (Eq, Show, Ord, Generic)

instance ToJSON GameResult
instance FromJSON GameResult

data GameView
    = GameView
        { _gvNumPlayers :: Int
        , _gvPlayerPosition :: Int
        , _gvPlayerState :: PlayerState
        , _gvOpponentViews :: [PlayerView]
        , _gvAvailableChips :: Map ChipType Int
        , _gvAvailableNobles :: [Noble]
        , _gvTier1View :: TierView
        , _gvTier2View :: TierView
        , _gvTier3View :: TierView
        , _gvCurrentRequest :: ActionRequest
        , _gvActionLog :: [(Int, ActionSummary)]
        }
    deriving (Eq, Show, Ord, Generic)

instance ToJSON GameView
instance FromJSON GameView

makeLenses ''Card
makeLenses ''Noble
makeLenses ''ActionRequest
makeLenses ''PlayerState
makeLenses ''TierState
makeLenses ''GameState
makeLenses ''PlayerView
makeLenses ''TierView
makeLenses ''GameView
