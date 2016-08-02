module Components.Client where

import Prelude
import Thermite as T

import React as R
import React.DOM as R
import React.DOM.Props as RP

import Browser.LocalStorage
import Control.Monad.Aff
import Control.Monad.Eff
import Control.Monad.Eff.Class
import Control.Monad.Eff.Console
import Control.Monad.Eff.Random
import Control.Monad.Rec.Class
import Control.Monad.Trans
import Data.Argonaut
import Data.Array as Array
import Data.Either
import Data.Foldable
import Data.Int as Int
import Data.Lens
import Data.List as List
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe
import Data.Generic
import Data.String as String
import Data.StrMap (StrMap)
import Data.StrMap as StrMap
import Data.Tuple

import Network.HTTP.Affjax
import Network.HTTP.StatusCode

import Components.PlayerInfo as PlayerInfo

import Splendor.Types

data ActionSelection
    = TakeChipsSelection (Array Color)
    | CardSelection CardId

derive instance genericActionSelection :: Generic ActionSelection

instance eqActionSelection :: Eq ActionSelection where
    eq = gEq

type ClientState =
    { clientKey :: String
    , playerInfo :: PlayerInfo
    , instanceList :: StrMap InstanceSummary
    , currentLobbyKey :: Maybe String
    , currentInstance :: Maybe InstanceView
    , currentSelection :: Maybe ActionSelection
    }

_playerInfo :: forall a b r. Lens { playerInfo :: a | r } { playerInfo :: b | r } a b
_playerInfo = lens _.playerInfo (_ { playerInfo = _ })

data ClientAction
    = OnPlayerInfo PlayerInfo.PlayerInfoAction
    | NewLobbyAction
    | JoinLobbyAction String
    | LeaveLobbyAction
    | StartGameAction
    | ClearSelection
    | SelectChip Color
    | SelectCard CardId
    | DoGameAction Action

newKey :: forall e. Eff (random :: RANDOM | e) String
newKey = go 40
    where
    go n =
        if n == 0
        then pure ""
        else do
            c <- randomInt 0 15
            rest <- go (n-1)
            pure $ (Int.toStringAs Int.hexadecimal c) <> rest

data StorageKey a = ClientKeyKey
derive instance genericStorageKey :: Generic (StorageKey a)

clientKeyKey :: StorageKey String
clientKeyKey = ClientKeyKey

initializeState :: forall e. Eff (storage :: STORAGE, random :: RANDOM | e) ClientState
initializeState = do
    storedKey <- localStorage.getItem clientKeyKey
    key <- case storedKey of
        Nothing -> do
            k <- newKey
            localStorage.setItem clientKeyKey k
            pure k
        Just k -> do
            pure k
    pInfo <- PlayerInfo.initializePlayerInfo
    pure $
        { clientKey: key
        , playerInfo: pInfo
        , instanceList: StrMap.empty :: StrMap InstanceSummary
        , currentLobbyKey: Nothing
        , currentInstance: Nothing
        , currentSelection: Nothing
        }

makeRequest :: forall a b e. (EncodeJson a, DecodeJson b) => ServerRequest a -> Aff ( ajax :: AJAX | e ) (Maybe b)
makeRequest req = do
    res <- post "/" (encodeJson req)
    if res.status == StatusCode 200
        then case decodeJson (res.response) of
            Left _ -> pure Nothing
            Right (ErrorResponse _) -> pure Nothing
            Right (OkResponse dat) ->
                case decodeJson dat of
                    Left _ -> pure Nothing
                    Right val -> pure (Just val)
        else pure Nothing

backgroundWork :: forall e. R.ReactThis _ ClientState -> Aff ( ajax :: AJAX, console :: CONSOLE | e ) Unit
backgroundWork rthis = forever do
    refreshLobbies rthis
    refreshGame rthis
    later' 1000 (pure unit)

refreshLobbies :: forall e. R.ReactThis _ ClientState -> Aff _ Unit
refreshLobbies rthis = do
    s <- liftEff $ R.readState rthis
    dat <- makeRequest (ServerRequest
        { playerKey: s.clientKey
        , requestData: ListLobbies
        })
    case dat of
        Nothing -> pure unit
        Just instances -> do
            liftEff $ R.transformState rthis (\state -> state { instanceList = instances })

refreshGame :: forall e. R.ReactThis _ ClientState -> Aff _ Unit
refreshGame rthis = do
    s <- liftEff $ R.readState rthis
    case s.currentLobbyKey of
        Nothing -> pure unit
        Just lobbyKey ->
            case s.currentInstance of
                Just (CompletedInstanceView _) -> pure unit
                _ -> do
                    instState <- makeRequest (ServerRequest
                        { playerKey: s.clientKey
                        , requestData: GetGameState lobbyKey
                        })
                    case instState of
                        Just _ ->
                            liftEff $ R.transformState rthis (\state -> state { currentInstance = instState })
                        Nothing ->
                            liftEff $ R.transformState rthis (\state -> state { currentLobbyKey = Nothing, currentInstance = Nothing })

-- Lifted specs for subcomponents
pInfoSpec = T.focusState _playerInfo PlayerInfo.spec

render :: T.Render ClientState _ _
render dispatch p state _ =
    case state.currentInstance of
        Nothing ->
            case state.currentLobbyKey of
                Nothing ->
                    [ R.div'
                        [ R.p'
                            [ R.text "Client Key: "
                            , R.text $ state.clientKey
                            ]
                        , R.div' $ (view T._render pInfoSpec) (dispatch <<< OnPlayerInfo)  p state []
                        , R.div' $ foldMap (\(Tuple lobbyKey lobbyView) ->
                            [ R.div' $
                                [ R.text "Lobby: "
                                , R.text lobbyKey
                                , R.text $ gShow lobbyView
                                , R.button
                                    [ RP.onClick \_ -> dispatch (JoinLobbyAction lobbyKey)
                                    ]
                                    [ R.text "Join"
                                    ]
                                ]
                            ]) (StrMap.toList state.instanceList)
                        , R.button
                            [ RP.onClick \_ -> dispatch NewLobbyAction
                            ]
                            [ R.text "New Game"
                            ]
                        ]
                    ]
                Just lobbyKey ->
                    [ R.text "Loading..."
                    , R.button
                        [ RP.onClick \_ -> dispatch LeaveLobbyAction
                        ]
                        [ R.text "Leave Game"
                        ]
                    ]
        Just inst ->
            case inst of
                WaitingInstanceView wiv ->
                    [ R.div' $
                        [ R.text "Waiting in lobby"
                        ]
                    , R.div' $
                        [ R.text "Players:" ]
                        <> foldMap (\(PlayerInfo p) ->
                            [ R.text " "
                            , R.text p.displayName
                            ]) wiv.waitingPlayers
                    , R.button
                        [ RP.onClick \_ -> dispatch LeaveLobbyAction
                        ]
                        [ R.text "Leave Game"
                        ]
                    , R.button
                        [ RP.onClick \_ -> dispatch StartGameAction
                        ]
                        [ R.text "Start Game"
                        ]
                    ]
                RunningInstanceView riv ->
                    [ R.div
                        [ RP.className "gameView"
                        ]
                        (renderGameView state.currentSelection dispatch p (riv.runningGame) [])
                    ]
                CompletedInstanceView civ ->
                    [ R.text "Completed game placeholder" ]

renderGameView :: Maybe ActionSelection -> T.Render (RunningGame GameView) _ _
renderGameView selection dispatch p (RunningGame rg) _ =
    case rg.gameState of
        GameView gv ->
            [ R.div
                [ RP.className "boardSupply" ]
                [ R.div
                    [ RP.className "availableChips" ]
                    (renderAvailableChips selection dispatch p gv.availableChips [])
                , R.div
                    [ RP.className "actionArea" ]
                    (renderActionButtons selection dispatch p (GameView gv) [])
                ]
            , R.div
                [ RP.className "tierView" ]
                (renderTierView selection dispatch p gv.tier3View [])
            , R.div
                [ RP.className "tierView" ]
                (renderTierView selection dispatch p gv.tier2View [])
            , R.div
                [ RP.className "tierView" ]
                (renderTierView selection dispatch p gv.tier1View [])
            , R.div
                [ RP.className "playerBoards" ]
                ([ R.div
                    [ RP.className "myBoard" ]
                    (renderPlayerState selection dispatch p gv.playerState [])
                ] <>
                map (\opp ->
                    R.div
                        [ RP.className "oppBoard" ]
                        []
                ) gv.opponentViews)
            ]

renderActionButtons :: Maybe ActionSelection -> T.Render GameView _ _
renderActionButtons selection dispatch p (GameView gv) _ =
    case selection of
        Nothing -> []
        Just (TakeChipsSelection colors) ->
            (if Array.length colors == min 3 numAvailableChipTypes
            then
                [ R.button
                    [ RP.onClick \_ -> dispatch (DoGameAction (Take3 (Array.index colors 0) (Array.index colors 1) (Array.index colors 2)))
                    ]
                    [ R.text "Take chips"
                    ]
                ]
            else [])
            <> (case Array.uncons colors of
                Just { head: c, tail: rest } ->
                    if Array.null rest && fromMaybe 0 (Map.lookup (Basic c) gv.availableChips) >= 4
                    then
                        [ R.button
                            [ RP.onClick \_ -> dispatch (DoGameAction (Take2 c))
                            ]
                            [ R.text "Take two"
                            ]
                        ]
                    else []
                _ -> [])
        Just (CardSelection cardId) ->
            -- TODO: Check legality of reserve/buy 
            [ R.button
                [ RP.onClick \_ -> dispatch (DoGameAction (Buy cardId))
                ]
                [ R.text "Buy"
                ]
            , R.button
                [ RP.onClick \_ -> dispatch (DoGameAction (Reserve cardId))
                ]
                [ R.text "Reserve"
                ]
            ]
    where
    numAvailableChipTypes = List.length <<< List.filter (\(Tuple _ n) -> n > 0) $ Map.toList gv.availableChips

renderTierView :: Maybe ActionSelection -> T.Render TierView _ _
renderTierView selection dispatch p (TierView tv) _ =
    map (\(Card c) ->
        R.div
            (let
            classes = if selection == Just (CardSelection c.id)
                then "selected card"
                else "card"
            in
            [ RP.className classes
            , RP.onClick \_ -> dispatch (SelectCard c.id)
            ])
            (renderCard dispatch p (Card c) [])
        ) tv.availableCards
    <> [ R.div
        [ RP.className "tierDeck"
        ]
        [ R.text (show tv.deckCount)
        ]
    ]

renderCard :: T.Render Card _ _
renderCard dispatch p (Card c) _ =
    [ R.div
        [ RP.className (String.joinWith " " ["cardTop", colorClass c.color])
        ]
        if c.points > 0
            then [ R.text (show c.points) ]
            else [ R.text "\x00a0" ]
    , R.div
        [ RP.className "cardPrice"
        ]
        (foldMap (\(Tuple c n) ->
            [ R.div
                [ RP.className (String.joinWith " " ["cardPriceComponent", colorClass c])
                ]
                [ R.text (show n)
                ]
            ]) (Map.toList c.cost)
        )
    ]

renderAvailableChips :: Maybe ActionSelection -> T.Render (Map ChipType Int) _ _
renderAvailableChips selection dispatch p chips _ =
    map (\ctype -> R.div
        [ RP.className "chipPlaceholder" ]
        (if chipNumber ctype chips > 0
            then
                [ R.div
                    (let
                    classes =
                        case selection of
                            Just (TakeChipsSelection colors) ->
                                if any (\c -> Basic c == ctype) colors
                                    then String.joinWith " " ["selected", "chip", chipColorClass ctype]
                                    else String.joinWith " " ["chip", chipColorClass ctype]
                            _ -> String.joinWith " " ["chip", chipColorClass ctype]
                    in
                    ([ RP.className classes
                    ] <>
                    case ctype of
                        Basic color -> [ RP.onClick \_ -> dispatch (SelectChip color) ]
                        Gold -> []
                    ))
                    [ R.text (show $ chipNumber ctype chips)
                    ]
                ]
            else []
        )
    ) [Basic Red, Basic Green, Basic Blue, Basic White, Basic Black, Gold]
    where
    chipNumber ctype chips =
        fromMaybe 0 (Map.lookup ctype chips)
    chipColorClass ctype =
        case ctype of
            Basic color -> colorClass color
            Gold -> "gold"

renderPlayerState :: Maybe ActionSelection -> T.Render PlayerState _ _
renderPlayerState selection dispatch p (PlayerState ps) _ =
    map (\color -> R.div
        [ RP.className "psGroup"
        ]
        [ R.div
            [ RP.className "ownedCards"
            ]
            (map (\card ->
                R.div
                    [ RP.className "card"
                    ]
                    (renderCard dispatch p card [])
                ) (Array.reverse $ Array.filter (\(Card c) -> c.color == color) ps.ownedCards)
            )
        , R.div
            [ RP.className "ownedChips"
            ]
            (if chipNumber (Basic color) ps.heldChips > 0
                then
                    [ R.div
                        [ RP.className (String.joinWith " " ["chip", colorClass color])
                        ]
                        [ R.text (show $ chipNumber (Basic color) ps.heldChips)
                        ]
                    ]
                else []
            )
        ]
    ) [Red, Green, Blue, White, Black] <>
    [ R.div
        [ RP.className "psSpecial"
        ]
        [ R.div
            [ RP.className "reservedCards"
            ]
            (map (\card ->
                R.div
                    [ RP.className "card"
                    ]
                    (renderCard dispatch p card [])
                ) (Array.reverse ps.reservedCards)
            )
        , R.div
            [ RP.className "ownedChips"
            ]
            (if chipNumber Gold ps.heldChips > 0
                then
                    [ R.div
                        [ RP.className "chip gold"
                        ]
                        [ R.text (show $ chipNumber Gold ps.heldChips)
                        ]
                    ]
                else []
            )
        ]
    ]
    where
    chipNumber ctype chips =
        fromMaybe 0 (Map.lookup ctype chips)

colorClass :: Color -> String
colorClass c =
    case c of
        Red -> "red"
        Green -> "green"
        Blue -> "blue"
        White -> "white"
        Black -> "black"

performAction :: T.PerformAction _ ClientState _ ClientAction
performAction a p s =
    case a of
        OnPlayerInfo a' -> do
            (view T._performAction pInfoSpec) a' p s
        NewLobbyAction -> do
            newLobbyKey <- lift $ makeRequest (ServerRequest
                { playerKey: s.clientKey
                , requestData: NewLobby s.playerInfo
                })
            void $ T.cotransform (\state -> state { currentLobbyKey = newLobbyKey })
        JoinLobbyAction lobbyKey -> do
            (_ :: Maybe Json) <- lift $ makeRequest (ServerRequest
                { playerKey: s.clientKey
                , requestData: JoinLobby lobbyKey s.playerInfo
                })
            void $ T.cotransform (\state -> state { currentLobbyKey = Just lobbyKey })
        LeaveLobbyAction -> do
            case s.currentLobbyKey of
                Nothing -> pure unit
                Just lobbyKey -> do
                    (dat :: Maybe Json) <- lift $ makeRequest (ServerRequest
                        { playerKey: s.clientKey
                        , requestData: LeaveLobby lobbyKey
                        })
                    case dat of
                        Nothing -> pure unit
                        Just _ -> void $ T.cotransform (\state -> state { currentLobbyKey = Nothing, currentInstance = Nothing })
        StartGameAction -> do
            case s.currentLobbyKey of
                Nothing -> pure unit
                Just lobbyKey -> do
                    (_ :: Maybe Json) <- lift $ makeRequest (ServerRequest
                        { playerKey: s.clientKey
                        , requestData: StartGame lobbyKey
                        })
                    pure unit
        ClearSelection -> do
            void $ T.cotransform (\state -> state { currentSelection = Nothing })
        SelectChip color -> do
            case s.currentSelection of
                Just (TakeChipsSelection selectedColors) ->
                    if any (\c -> c == color) selectedColors
                        then do
                            void $ T.cotransform (\state -> state { currentSelection = Just $ TakeChipsSelection (Array.filter (\c -> c /= color) selectedColors) })
                        else do
                            void $ T.cotransform (\state -> state { currentSelection = Just $ TakeChipsSelection (Array.snoc selectedColors color) })
                _ -> do
                    void $ T.cotransform (\state -> state { currentSelection = Just $ TakeChipsSelection [color] })
        SelectCard cardId -> do
            if s.currentSelection == Just (CardSelection cardId)
                then void $ T.cotransform (\state -> state { currentSelection = Nothing })
                else void $ T.cotransform (\state -> state { currentSelection = Just $ CardSelection cardId })
        DoGameAction action -> do
            case s.currentLobbyKey of
                Nothing -> pure unit
                Just gameKey -> do
                    (dat :: Maybe Json) <- lift $ makeRequest (ServerRequest
                        { playerKey: s.clientKey
                        , requestData: GameAction gameKey action
                        })
                    case dat of
                        Nothing -> pure unit
                        Just _ -> do
                            void $ T.cotransform (\state -> state { currentSelection = Nothing })

spec :: T.Spec _ ClientState _ ClientAction
spec = T.simpleSpec performAction render
