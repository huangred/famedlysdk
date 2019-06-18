/*
 * Copyright (c) 2019 Zender & Kurtz GbR.
 *
 * Authors:
 *   Christian Pauly <krille@famedly.com>
 *   Marcel Radzio <mtrnord@famedly.com>
 *
 * This file is part of famedlysdk.
 *
 * famedlysdk is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * famedlysdk is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Foobar.  If not, see <http://www.gnu.org/licenses/>.
 */

import 'package:famedlysdk/src/Client.dart';
import 'package:famedlysdk/src/utils/ChatTime.dart';
import 'package:famedlysdk/src/utils/MxContent.dart';
import 'package:famedlysdk/src/responses/ErrorResponse.dart';
import 'package:famedlysdk/src/sync/EventUpdate.dart';
import 'package:famedlysdk/src/Event.dart';
import './User.dart';

/// Represents a Matrix room.
class Room {
  /// The full qualified Matrix ID for the room in the format '!localid:server.abc'.
  final String id;

  /// Membership status of the user for this room.
  String membership;

  /// The name of the room if set by a participant.
  String name;

  /// The topic of the room if set by a participant.
  String topic;

  /// The avatar of the room if set by a participant.
  MxContent avatar = MxContent("");

  /// The count of unread notifications.
  int notificationCount;

  /// The count of highlighted notifications.
  int highlightCount;

  String prev_batch;

  String draft;

  /// Time when the user has last read the chat.
  ChatTime unread;

  /// ID of the fully read marker event.
  String fullyRead;

  /// The address in the format: #roomname:homeserver.org.
  String canonicalAlias;

  /// If this room is a direct chat, this is the matrix ID of the user
  String directChatMatrixID;

  /// Must be one of [all, mention]
  String notificationSettings;

  /// Are guest users allowed?
  String guestAccess;

  /// Who can see the history of this room?
  String historyVisibility;

  /// Who is allowed to join this room?
  String joinRules;

  /// The needed power levels for all actions.
  Map<String, int> powerLevels = {};

  /// The list of events in this room. If the room is created by the
  /// [getRoomList()] of the [Store], this will contain only the last event.
  List<Event> events = [];

  /// The list of participants in this room. If the room is created by the
  /// [getRoomList()] of the [Store], this will contain only the sender of the
  /// last event.
  List<User> participants = [];

  /// Your current client instance.
  final Client client;

  @Deprecated("Rooms.roomID is deprecated! Use Rooms.id instead!")
  String get roomID => this.id;

  @Deprecated("Rooms.matrix is deprecated! Use Rooms.client instead!")
  Client get matrix => this.client;

  @Deprecated("Rooms.status is deprecated! Use Rooms.membership instead!")
  String get status => this.membership;

  Room({
    this.id,
    this.membership,
    this.name,
    this.topic,
    this.avatar,
    this.notificationCount,
    this.highlightCount,
    this.prev_batch,
    this.draft,
    this.unread,
    this.fullyRead,
    this.canonicalAlias,
    this.directChatMatrixID,
    this.notificationSettings,
    this.guestAccess,
    this.historyVisibility,
    this.joinRules,
    this.powerLevels,
    this.events,
    this.participants,
    this.client,
  });

  /// The last message sent to this room.
  String get lastMessage {
    if (events?.length > 0)
      return events[0].getBody();
    else
      return "";
  }

  /// When the last message received.
  ChatTime get timeCreated {
    if (events?.length > 0)
      return events[0].time;
    else
      return ChatTime.now();
  }

  /// Call the Matrix API to change the name of this room.
  Future<dynamic> setName(String newName) async {
    dynamic res = await client.connection.jsonRequest(
        type: "PUT",
        action: "/client/r0/rooms/${id}/send/m.room.name/${new DateTime.now()}",
        data: {"name": newName});
    if (res is ErrorResponse) client.connection.onError.add(res);
    return res;
  }

  /// Call the Matrix API to change the topic of this room.
  Future<dynamic> setDescription(String newName) async {
    dynamic res = await client.connection.jsonRequest(
        type: "PUT",
        action:
            "/client/r0/rooms/${id}/send/m.room.topic/${new DateTime.now()}",
        data: {"topic": newName});
    if (res is ErrorResponse) client.connection.onError.add(res);
    return res;
  }

  @Deprecated("Use the client.connection streams instead!")
  Stream<List<Event>> get eventsStream {
    return Stream<List<Event>>.fromIterable(Iterable<List<Event>>.generate(
        this.events.length, (int index) => this.events)).asBroadcastStream();
  }

  /// Call the Matrix API to send a simple text message.
  Future<dynamic> sendText(String message, {String txid = null}) async {
    if (txid == null) txid = "txid${DateTime.now().millisecondsSinceEpoch}";
    final dynamic res = await client.connection.jsonRequest(
        type: "PUT",
        action: "/client/r0/rooms/${id}/send/m.room.message/$txid",
        data: {"msgtype": "m.text", "body": message});
    if (res["errcode"] == "M_LIMIT_EXCEEDED")
      client.connection.onError.add(res["error"]);
    return res;
  }

  Future<String> sendTextEvent(String message) async {
    final String type = "m.room.message";
    final int now = DateTime.now().millisecondsSinceEpoch;
    final String messageID = "msg$now";

    EventUpdate eventUpdate =
        EventUpdate(type: type, roomID: id, eventType: "timeline", content: {
      "type": type,
      "id": messageID,
      "sender": client.userID,
      "status": 0,
      "origin_server_ts": now,
      "content": {
        "msgtype": "m.text",
        "body": message,
      }
    });
    client.connection.onEvent.add(eventUpdate);
    await client.store.transaction(() {
      client.store.storeEventUpdate(eventUpdate);
    });
    final dynamic res = await sendText(message, txid: messageID);
    if (res is ErrorResponse) {
      client.store.db
          .rawUpdate("UPDATE Events SET status=-1 WHERE id=?", [messageID]);
    } else {
      final String newEventID = res["event_id"];
      final List<Map<String, dynamic>> event = await client.store.db
          .rawQuery("SELECT * FROM Events WHERE id=?", [newEventID]);
      if (event.length > 0) {
        client.store.db.rawDelete("DELETE FROM Events WHERE id=?", [messageID]);
      } else {
        client.store.db.rawUpdate("UPDATE Events SET id=?, status=1 WHERE id=?",
            [newEventID, messageID]);
      }
      return newEventID;
    }
    return null;
  }

  /// Call the Matrix API to leave this room.
  Future<dynamic> leave() async {
    dynamic res = await client.connection
        .jsonRequest(type: "POST", action: "/client/r0/rooms/${id}/leave");
    if (res is ErrorResponse) client.connection.onError.add(res);
    return res;
  }

  /// Call the Matrix API to forget this room if you already left it.
  Future<dynamic> forget() async {
    client.store.forgetRoom(id);
    dynamic res = await client.connection
        .jsonRequest(type: "POST", action: "/client/r0/rooms/${id}/forget");
    if (res is ErrorResponse) client.connection.onError.add(res);
    return res;
  }

  /// Call the Matrix API to kick a user from this room.
  Future<dynamic> kick(String userID) async {
    dynamic res = await client.connection.jsonRequest(
        type: "POST",
        action: "/client/r0/rooms/${id}/kick",
        data: {"user_id": userID});
    if (res is ErrorResponse) client.connection.onError.add(res);
    return res;
  }

  /// Call the Matrix API to ban a user from this room.
  Future<dynamic> ban(String userID) async {
    dynamic res = await client.connection.jsonRequest(
        type: "POST",
        action: "/client/r0/rooms/${id}/ban",
        data: {"user_id": userID});
    if (res is ErrorResponse) client.connection.onError.add(res);
    return res;
  }

  /// Call the Matrix API to unban a banned user from this room.
  Future<dynamic> unban(String userID) async {
    dynamic res = await client.connection.jsonRequest(
        type: "POST",
        action: "/client/r0/rooms/${id}/unban",
        data: {"user_id": userID});
    if (res is ErrorResponse) client.connection.onError.add(res);
    return res;
  }

  /// Call the Matrix API to unban a banned user from this room.
  Future<dynamic> setPower(String userID, int power) async {
    Map<String, int> powerMap = await client.store.getPowerLevels(id);
    powerMap[userID] = power;

    dynamic res = await client.connection.jsonRequest(
        type: "PUT",
        action: "/client/r0/rooms/$id/state/m.room.power_levels/",
        data: {"users": powerMap});
    if (res is ErrorResponse) client.connection.onError.add(res);
    return res;
  }

  /// Call the Matrix API to invite a user to this room.
  Future<dynamic> invite(String userID) async {
    dynamic res = await client.connection.jsonRequest(
        type: "POST",
        action: "/client/r0/rooms/${id}/invite",
        data: {"user_id": userID});
    if (res is ErrorResponse) client.connection.onError.add(res);
    return res;
  }

  /// Request more previous events from the server.
  Future<void> requestHistory({int historyCount = 100}) async {
    final dynamic resp = client.connection.jsonRequest(
        type: "GET",
        action: "/client/r0/rooms/$id/messages",
        data: {"from": prev_batch, "dir": "b", "limit": historyCount});

    if (resp is ErrorResponse) return;

    if (!(resp["chunk"] is List<dynamic> &&
        resp["chunk"].length > 0 &&
        resp["end"] is String)) return;

    List<dynamic> history = resp["chunk"];
    client.store.transaction(() {
      for (int i = 0; i < history.length; i++) {
        EventUpdate eventUpdate = EventUpdate(
          eventType: "history",
          roomID: id,
          type: history[i]["type"],
          content: history[i],
        );
        client.connection.onEvent.add(eventUpdate);
        client.store.storeEventUpdate(eventUpdate);
        client.store.txn.rawUpdate(
            "UPDATE Rooms SET prev_batch=? WHERE id=?", [resp["end"], id]);
      }
    });
  }

  Future<dynamic> addToDirectChat(String userID) async {
    Map<String, List<String>> directChats =
        await client.store.getAccountDataDirectChats();
    if (directChats.containsKey(userID)) if (!directChats[userID].contains(id))
      directChats[userID].add(id);
    else
      return null; // Is already in direct chats
    else
      directChats[userID] = [id];

    final resp = await client.connection.jsonRequest(
        type: "PUT",
        action: "/client/r0/user/${client.userID}/account_data/m.direct",
        data: directChats);
    return resp;
  }

  Future<dynamic> sendReadReceipt(String eventID) async {
    final dynamic resp = client.connection.jsonRequest(
        type: "POST",
        action: "/client/r0/rooms/$id/read_markers",
        data: {
          "m.fully_read": eventID,
          "m.read": eventID,
        });
    return resp;
  }

  /// Returns a Room from a json String which comes normally from the store.
  static Future<Room> getRoomFromTableRow(
      Map<String, dynamic> row, Client matrix) async {
    String name = row["topic"];
    if (name == "")
      name = await matrix.store?.getChatNameFromMemberNames(row["id"]) ?? "";

    String avatarUrl = row["avatar_url"];
    if (avatarUrl == "")
      avatarUrl = await matrix.store?.getAvatarFromSingleChat(row["id"]) ?? "";

    return Room(
      id: row["id"],
      name: name,
      membership: row["membership"],
      topic: row["description"],
      avatar: MxContent(avatarUrl),
      notificationCount: row["notification_count"],
      highlightCount: row["highlight_count"],
      unread: ChatTime(row["unread"]),
      fullyRead: row["fully_read"],
      notificationSettings: row["notification_settings"],
      directChatMatrixID: row["direct_chat_matrix_id"],
      draft: row["draft"],
      prev_batch: row["prev_batch"],
      guestAccess: row["guest_access"],
      historyVisibility: row["history_visibility"],
      joinRules: row["join_rules"],
      powerLevels: {
        "power_events_default": row["power_events_default"],
        "power_state_default": row["power_state_default"],
        "power_redact": row["power_redact"],
        "power_invite": row["power_invite"],
        "power_ban": row["power_ban"],
        "power_kick": row["power_kick"],
        "power_user_default": row["power_user_default"],
        "power_event_avatar": row["power_event_avatar"],
        "power_event_history_visibility": row["power_event_history_visibility"],
        "power_event_canonical_alias": row["power_event_canonical_alias"],
        "power_event_aliases": row["power_event_aliases"],
        "power_event_name": row["power_event_name"],
        "power_event_power_levels": row["power_event_power_levels"],
      },
      client: matrix,
      events: [Event.fromJson(row, null)],
      participants: [],
    );
  }

  @Deprecated("Use client.store.getRoomById(String id) instead!")
  static Future<Room> getRoomById(String id, Client matrix) async {
    Room room = await matrix.store.getRoomById(id);
    return room;
  }

  /// Load a room from the store including all room events.
  static Future<Room> loadRoomEvents(String id, Client matrix) async {
    Room room = await matrix.store.getRoomById(id);
    await room.loadEvents();
    return room;
  }

  /// Load all events for a given room from the store. This includes all
  /// senders of those events, who will be added to the participants list.
  Future<List<Event>> loadEvents() async {
    this.events = await client.store.getEventList(this);

    Map<String, bool> participantMap = {};
    for (num i = 0; i < events.length; i++) {
      if (!participantMap.containsKey(events[i].sender.mxid)) {
        participants.add(events[i].sender);
        participantMap[events[i].sender.mxid] = true;
      }
    }

    return this.events;
  }

  /// Load all participants for a given room from the store.
  Future<List<User>> loadParticipants() async {
    this.participants = await client.store.loadParticipants(this);
    return this.participants;
  }

  /// Request the full list of participants from the server. The local list
  /// from the store is not complete if the client uses lazy loading.
  Future<List<User>> requestParticipants() async {
    List<User> participants = [];

    dynamic res = await client.connection
        .jsonRequest(type: "GET", action: "/client/r0/rooms/${id}/members");
    if (res is ErrorResponse || !(res["chunk"] is List<dynamic>))
      return participants;

    for (num i = 0; i < res["chunk"].length; i++) {
      User newUser = User(res["chunk"][i]["state_key"],
          displayName: res["chunk"][i]["content"]["displayname"] ?? "",
          membership: res["chunk"][i]["content"]["membership"] ?? "",
          avatarUrl: MxContent(res["chunk"][i]["content"]["avatar_url"] ?? ""),
          room: this);
      if (newUser.membership != "leave") participants.add(newUser);
    }

    this.participants = participants;

    return this.participants;
  }
}
