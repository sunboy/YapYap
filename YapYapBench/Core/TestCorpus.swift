// TestCorpus.swift
// YapYapBench — Hardcoded test transcripts for automated quality testing
import Foundation

struct CorpusEntry: Codable {
    let id: String
    let category: String
    let rawText: String
    let tags: Set<String>  // Used by QualityScorer to decide which checks apply

    // Tag constants
    static let hasFillers = "has_fillers"
    static let hasSelfCorrection = "has_self_correction"
    static let hasList = "has_list"
    static let hasTechnicalTerms = "has_technical_terms"
    static let hasMentions = "has_mentions"
    static let isShort = "is_short"
    static let isLong = "is_long"
    static let hasWhisperArtifacts = "has_whisper_artifacts"
    static let expectsFormal = "expects_formal"
    static let expectsCasual = "expects_casual"
}

struct TestCorpus {
    static let entries: [CorpusEntry] = fillerHeavy + selfCorrections + technical
        + shortPhrases + longDictation + lists + whisperArtifacts + mixedFormality
        + appSpecific + edgeCases

    // MARK: - Filler-Heavy (6 entries)
    private static let fillerHeavy: [CorpusEntry] = [
        CorpusEntry(
            id: "filler-01",
            category: "filler-heavy",
            rawText: "um so like i was thinking we should uh probably have a meeting tomorrow to discuss the uh project timeline you know",
            tags: [CorpusEntry.hasFillers]
        ),
        CorpusEntry(
            id: "filler-02",
            category: "filler-heavy",
            rawText: "basically what happened was like the server went down at um 3 am and you know nobody was monitoring it so it was like down for two hours before anyone noticed",
            tags: [CorpusEntry.hasFillers, CorpusEntry.hasTechnicalTerms]
        ),
        CorpusEntry(
            id: "filler-03",
            category: "filler-heavy",
            rawText: "so uh i just wanted to like touch base about the uh quarterly review and um see if everyone has their um reports ready you know for the presentation",
            tags: [CorpusEntry.hasFillers, CorpusEntry.expectsFormal]
        ),
        CorpusEntry(
            id: "filler-04",
            category: "filler-heavy",
            rawText: "hey so like basically the thing is um the new design looks really good but uh we need to like fix the spacing on the uh header component",
            tags: [CorpusEntry.hasFillers, CorpusEntry.hasTechnicalTerms]
        ),
        CorpusEntry(
            id: "filler-05",
            category: "filler-heavy",
            rawText: "i mean honestly like the api response time is uh kind of slow and we should probably um look into caching or something you know",
            tags: [CorpusEntry.hasFillers, CorpusEntry.hasTechnicalTerms]
        ),
        CorpusEntry(
            id: "filler-06",
            category: "filler-heavy",
            rawText: "so um yeah like i was going to say that the budget is basically sort of like tight this quarter and um we need to like prioritize",
            tags: [CorpusEntry.hasFillers]
        ),
    ]

    // MARK: - Self-Corrections (5 entries)
    private static let selfCorrections: [CorpusEntry] = [
        CorpusEntry(
            id: "selfcorrect-01",
            category: "self-correction",
            rawText: "send the report to john no wait send it to sarah she's the one handling that project now",
            tags: [CorpusEntry.hasSelfCorrection]
        ),
        CorpusEntry(
            id: "selfcorrect-02",
            category: "self-correction",
            rawText: "the meeting is on tuesday i mean wednesday at 3 pm in the large conference room",
            tags: [CorpusEntry.hasSelfCorrection]
        ),
        CorpusEntry(
            id: "selfcorrect-03",
            category: "self-correction",
            rawText: "we should use postgres or actually no lets go with redis for the caching layer its much faster for this use case",
            tags: [CorpusEntry.hasSelfCorrection, CorpusEntry.hasTechnicalTerms]
        ),
        CorpusEntry(
            id: "selfcorrect-04",
            category: "self-correction",
            rawText: "i think the deadline is friday or not friday scratch that its next monday because of the holiday",
            tags: [CorpusEntry.hasSelfCorrection]
        ),
        CorpusEntry(
            id: "selfcorrect-05",
            category: "self-correction",
            rawText: "um can you review the pull request on the main branch sorry i mean the feature branch the one with the authentication changes",
            tags: [CorpusEntry.hasSelfCorrection, CorpusEntry.hasFillers, CorpusEntry.hasTechnicalTerms]
        ),
    ]

    // MARK: - Technical Content (5 entries)
    private static let technical: [CorpusEntry] = [
        CorpusEntry(
            id: "tech-01",
            category: "technical",
            rawText: "the null pointer exception is happening in the getUserProfile method when the auth token is expired and the refresh token endpoint returns a 401",
            tags: [CorpusEntry.hasTechnicalTerms]
        ),
        CorpusEntry(
            id: "tech-02",
            category: "technical",
            rawText: "we need to update the docker compose yaml to add the new redis container and make sure the environment variables are set for the connection string",
            tags: [CorpusEntry.hasTechnicalTerms]
        ),
        CorpusEntry(
            id: "tech-03",
            category: "technical",
            rawText: "check the kubernetes pod logs for the api gateway service the health check endpoint slash health is returning 503 service unavailable",
            tags: [CorpusEntry.hasTechnicalTerms]
        ),
        CorpusEntry(
            id: "tech-04",
            category: "technical",
            rawText: "the swift ui view modifier isnt working because we need to conform to the view protocol and add the at environment object wrapper for the data store",
            tags: [CorpusEntry.hasTechnicalTerms]
        ),
        CorpusEntry(
            id: "tech-05",
            category: "technical",
            rawText: "run npm install dash dash save dev at types slash react then update the tsconfig json to include the new type declarations",
            tags: [CorpusEntry.hasTechnicalTerms]
        ),
    ]

    // MARK: - Short Phrases (5 entries)
    private static let shortPhrases: [CorpusEntry] = [
        CorpusEntry(
            id: "short-01",
            category: "short",
            rawText: "sounds good lets do it",
            tags: [CorpusEntry.isShort, CorpusEntry.expectsCasual]
        ),
        CorpusEntry(
            id: "short-02",
            category: "short",
            rawText: "can you send me the link",
            tags: [CorpusEntry.isShort]
        ),
        CorpusEntry(
            id: "short-03",
            category: "short",
            rawText: "ill be there in five minutes",
            tags: [CorpusEntry.isShort, CorpusEntry.expectsCasual]
        ),
        CorpusEntry(
            id: "short-04",
            category: "short",
            rawText: "um yeah sure thing",
            tags: [CorpusEntry.isShort, CorpusEntry.hasFillers, CorpusEntry.expectsCasual]
        ),
        CorpusEntry(
            id: "short-05",
            category: "short",
            rawText: "please review the attached document and let me know your thoughts",
            tags: [CorpusEntry.isShort, CorpusEntry.expectsFormal]
        ),
    ]

    // MARK: - Long Dictation (4 entries)
    private static let longDictation: [CorpusEntry] = [
        CorpusEntry(
            id: "long-01",
            category: "long",
            rawText: "so i wanted to give everyone an update on the project status we finished the backend api work last week and the team is now focused on the frontend integration the main blocker right now is the authentication flow which needs to be refactored to support the new oauth provider we expect that to take about three days and then we can move on to the testing phase the qa team has already started writing test cases based on the requirements document",
            tags: [CorpusEntry.isLong, CorpusEntry.hasFillers]
        ),
        CorpusEntry(
            id: "long-02",
            category: "long",
            rawText: "hi team i wanted to follow up on our discussion from yesterday about the database migration plan so the current approach is to use a blue green deployment strategy where we run both the old and new databases in parallel for about a week this lets us validate the data integrity before cutting over completely the rollback plan is to simply switch the connection string back to the old database if we encounter any issues during the migration window",
            tags: [CorpusEntry.isLong, CorpusEntry.hasTechnicalTerms]
        ),
        CorpusEntry(
            id: "long-03",
            category: "long",
            rawText: "um ok so like the thing with the new feature is that we basically need to um rethink the whole user onboarding flow because right now its like really confusing for new users they sign up and then they have to go through like five different screens before they can actually use the product and uh we've been getting a lot of complaints about this so i think we should like simplify it to maybe two or three screens max and um focus on getting them to their first aha moment as quickly as possible",
            tags: [CorpusEntry.isLong, CorpusEntry.hasFillers]
        ),
        CorpusEntry(
            id: "long-04",
            category: "long",
            rawText: "dear hiring manager i am writing to express my interest in the senior software engineer position at your company i have over eight years of experience in full stack development specializing in react typescript and node js in my current role i lead a team of five engineers and have successfully delivered multiple high impact projects including a real time collaboration platform that serves over fifty thousand daily active users i am particularly excited about this opportunity because of your companys focus on developer tools",
            tags: [CorpusEntry.isLong, CorpusEntry.expectsFormal]
        ),
    ]

    // MARK: - Lists/Enumerations (4 entries)
    private static let lists: [CorpusEntry] = [
        CorpusEntry(
            id: "list-01",
            category: "list",
            rawText: "for the sprint we need to do three things first fix the login bug second deploy the new api endpoints and third update the documentation",
            tags: [CorpusEntry.hasList]
        ),
        CorpusEntry(
            id: "list-02",
            category: "list",
            rawText: "the priorities for this week are number one finish the code review number two merge the feature branch number three start the database migration and number four update the monitoring dashboards",
            tags: [CorpusEntry.hasList, CorpusEntry.hasTechnicalTerms]
        ),
        CorpusEntry(
            id: "list-03",
            category: "list",
            rawText: "i need to pick up groceries get gas drop off the package at the post office and also call the dentist to reschedule my appointment",
            tags: [CorpusEntry.hasList, CorpusEntry.expectsCasual]
        ),
        CorpusEntry(
            id: "list-04",
            category: "list",
            rawText: "the issues we found in the audit are one the ssl certificate is about to expire two the backup scripts havent run in three days and three the disk usage on the prod server is at ninety two percent",
            tags: [CorpusEntry.hasList, CorpusEntry.hasTechnicalTerms]
        ),
    ]

    // MARK: - Whisper Artifacts (3 entries)
    private static let whisperArtifacts: [CorpusEntry] = [
        CorpusEntry(
            id: "whisper-01",
            category: "whisper-artifact",
            rawText: "[BLANK_AUDIO] hey can you check the deployment status [BLANK_AUDIO]",
            tags: [CorpusEntry.hasWhisperArtifacts]
        ),
        CorpusEntry(
            id: "whisper-02",
            category: "whisper-artifact",
            rawText: "the meeting is at 3 pm the meeting is at 3 pm in the main conference room",
            tags: [CorpusEntry.hasWhisperArtifacts]
        ),
        CorpusEntry(
            id: "whisper-03",
            category: "whisper-artifact",
            rawText: "thanks for watching thanks for watching please subscribe and like the video the actual message is can you review my pull request",
            tags: [CorpusEntry.hasWhisperArtifacts]
        ),
    ]

    // MARK: - Mixed Formality (4 entries)
    private static let mixedFormality: [CorpusEntry] = [
        CorpusEntry(
            id: "formal-01",
            category: "formality",
            rawText: "i would like to schedule a meeting with the executive team to discuss our q3 strategy and review the preliminary budget allocations",
            tags: [CorpusEntry.expectsFormal]
        ),
        CorpusEntry(
            id: "formal-02",
            category: "formality",
            rawText: "pursuant to our earlier conversation i wanted to confirm that the contract terms have been reviewed by legal and we can proceed with the signing",
            tags: [CorpusEntry.expectsFormal]
        ),
        CorpusEntry(
            id: "casual-01",
            category: "formality",
            rawText: "yo did you see that new feature they shipped its pretty sick honestly way better than what we had before",
            tags: [CorpusEntry.expectsCasual]
        ),
        CorpusEntry(
            id: "casual-02",
            category: "formality",
            rawText: "lol yeah the demo totally crashed but we played it off and nobody noticed haha",
            tags: [CorpusEntry.expectsCasual]
        ),
    ]

    // MARK: - App-Specific (8 entries)
    private static let appSpecific: [CorpusEntry] = [
        CorpusEntry(
            id: "app-slack-01",
            category: "app-specific",
            rawText: "hey @mike can you check the #deployments channel the latest build failed and @sarah already opened a ticket",
            tags: [CorpusEntry.hasMentions, CorpusEntry.hasTechnicalTerms, CorpusEntry.expectsCasual]
        ),
        CorpusEntry(
            id: "app-slack-02",
            category: "app-specific",
            rawText: "posted in #general at everyone please review the new onboarding doc before friday and add your comments in the thread",
            tags: [CorpusEntry.hasMentions, CorpusEntry.expectsCasual]
        ),
        CorpusEntry(
            id: "app-email-01",
            category: "app-specific",
            rawText: "hi david thank you for your prompt response regarding the proposal i have reviewed the terms and would like to suggest a few amendments particularly around the payment schedule and the intellectual property clauses please find my detailed comments in the attached document",
            tags: [CorpusEntry.expectsFormal, CorpusEntry.isLong]
        ),
        CorpusEntry(
            id: "app-email-02",
            category: "app-specific",
            rawText: "dear team please be advised that the office will be closed next monday for the national holiday all pending deliverables should be completed by end of day friday please plan accordingly",
            tags: [CorpusEntry.expectsFormal]
        ),
        CorpusEntry(
            id: "app-code-01",
            category: "app-specific",
            rawText: "add a guard let statement to unwrap the optional user id and throw an authentication error if its nil then pass it to the fetch profile async function",
            tags: [CorpusEntry.hasTechnicalTerms]
        ),
        CorpusEntry(
            id: "app-code-02",
            category: "app-specific",
            rawText: "the handleSubmit function needs to validate the form data check that email matches the regex pattern and password is at least 8 characters before calling the api",
            tags: [CorpusEntry.hasTechnicalTerms]
        ),
        CorpusEntry(
            id: "app-imessage-01",
            category: "app-specific",
            rawText: "hey wanna grab lunch today im thinking that new thai place on main street",
            tags: [CorpusEntry.expectsCasual, CorpusEntry.isShort]
        ),
        CorpusEntry(
            id: "app-imessage-02",
            category: "app-specific",
            rawText: "running late be there in 10 sorry traffic is insane today",
            tags: [CorpusEntry.expectsCasual, CorpusEntry.isShort]
        ),
    ]

    // MARK: - Edge Cases (4 entries)
    private static let edgeCases: [CorpusEntry] = [
        CorpusEntry(
            id: "edge-01",
            category: "edge-case",
            rawText: "um uh like you know basically sort of",
            tags: [CorpusEntry.hasFillers, CorpusEntry.isShort]
        ),
        CorpusEntry(
            id: "edge-02",
            category: "edge-case",
            rawText: "yes",
            tags: [CorpusEntry.isShort]
        ),
        CorpusEntry(
            id: "edge-03",
            category: "edge-case",
            rawText: "   ",
            tags: [CorpusEntry.isShort]
        ),
        CorpusEntry(
            id: "edge-04",
            category: "edge-case",
            rawText: "the the the the server is is is down down down and and nobody nobody is responding",
            tags: [CorpusEntry.hasWhisperArtifacts]
        ),
    ]
}
