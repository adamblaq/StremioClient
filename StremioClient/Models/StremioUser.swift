import Foundation

struct StremioUser: Codable {
    let id: String
    let email: String
    let fullname: String?
    let avatar: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case email, fullname, avatar
    }
}
